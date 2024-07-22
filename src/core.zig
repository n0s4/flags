const std = @import("std");
const format = @import("format.zig");
const help = @import("help.zig");
const check = @import("check.zig");

const compileError = check.compileError;

const ArgIterator = std.process.ArgIterator;

pub fn PositionalHandler(comptime Error: type) type {
    return struct {
        context: *anyopaque,
        handleFn: *const fn (context: *anyopaque, arg: []const u8) Error!void,

        fn handle(handler: @This(), arg: []const u8) Error!void {
            return handler.handleFn(handler.context, arg);
        }
    };
}

/// Prints the formatted error message to stderr and exits with status code 1.
pub fn fatal(comptime message: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("error: " ++ message ++ ".\n", args) catch {};
    std.process.exit(1);
}

pub fn printHelp(comptime Command: type, comptime command_name: []const u8) noreturn {
    const message = comptime if (@hasDecl(Command, "full_help")) blk: {
        if (!check.isString(@TypeOf(Command.full_help))) {
            compileError("'full_help' is not a string", .{});
        }
        break :blk Command.full_help;
    } else help.helpMessage(Command, command_name);

    std.io.getStdOut().writeAll(message) catch |err| {
        fatal("could not write help to stdout: {!}", .{err});
    };

    std.process.exit(0);
}

pub fn parse(
    args: *ArgIterator,
    comptime Command: type,
    comptime command_name: []const u8,
    comptime HandleError: type,
    pos_handler: PositionalHandler(HandleError),
) HandleError!Command {
    return switch (@typeInfo(Command)) {
        .Union => parseCommands(args, Command, command_name, HandleError, pos_handler),
        .Struct => parseFlags(args, Command, command_name, HandleError, pos_handler),
        else => comptime unreachable,
    };
}

fn parseCommands(
    args: *ArgIterator,
    comptime Commands: type,
    comptime command_name: []const u8,
    comptime HandleError: type,
    pos_handler: PositionalHandler(HandleError),
) HandleError!Commands {
    const arg = args.next() orelse fatal("expected subcommand", .{});

    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        printHelp(Commands, command_name);
    }

    inline for (std.meta.fields(Commands)) |command| {
        if (std.mem.eql(u8, comptime format.toKebab(command.name), arg)) {
            const sub_result = try parse(
                args,
                command.type,
                command_name ++ " " ++ command.name,
                HandleError,
                pos_handler,
            );

            return @unionInit(Commands, command.name, sub_result);
        }
    }

    fatal("unrecognized subcommand: '{s}'. see {s} --help", .{ arg, command_name });
}

fn parseFlags(
    args: *ArgIterator,
    comptime Flags: type,
    comptime command_name: []const u8,
    comptime HandleError: type,
    pos_handler: PositionalHandler(HandleError),
) HandleError!Flags {
    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    next_arg: while (args.next()) |arg| {
        if (arg.len == 0) fatal("empty argument", .{});

        if (arg[0] != '-') {
            try pos_handler.handle(arg);
            continue :next_arg;
        }

        if (arg.len == 1) fatal("unrecognized argument: '-'", .{});

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat the remaining flags as positional arguments
            while (args.next()) |positional| {
                try pos_handler.handle(positional);
            }
            break;
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp(Flags, command_name);
        }

        if (arg[1] == '-') {
            inline for (std.meta.fields(Flags)) |field| {
                comptime if (std.mem.eql(u8, field.name, "help")) {
                    compileError("flag name 'help' is reserved for showing help", .{});
                };

                if (std.mem.eql(u8, arg, format.flagName(field))) {
                    @field(passed, field.name) = true;

                    @field(flags, field.name) = parseArg(field.type, args, format.flagName(field));

                    continue :next_arg;
                }
            }
            fatal("unrecognized flag: {s}", .{arg});
        }

        if (@hasDecl(Flags, "switches")) {
            const Switches = @TypeOf(Flags.switches);
            const fields = std.meta.fields(Switches);

            comptime { // validation
                if (@typeInfo(Switches) != .Struct) {
                    compileError("'switches' is not a struct", .{});
                }
                for (fields, 0..) |field, field_idx| {
                    if (!@hasField(Flags, field.name)) compileError(
                        "switch name does not match any fields: '{s}'",
                        .{field.name},
                    );

                    if (field.type != comptime_int) compileError(
                        "invalid switch type for '{s}': {s}",
                        .{ field.name, @typeName(field.type) },
                    );

                    const switch_val = @field(Flags.switches, field.name);
                    switch (switch_val) {
                        'a'...'z', 'A'...'Z' => if (switch_val == 'h') compileError(
                            "switch value 'h' is reserved for the help message",
                            .{},
                        ),
                        else => compileError(
                            "switch value for '{s}' is not a letter",
                            .{field.name},
                        ),
                    }

                    for (fields[field_idx + 1 ..]) |other_field| {
                        const other = @field(Flags.switches, other_field.name);
                        if (switch_val == other) compileError(
                            "duplicated switch values: '{s}' and '{s}'",
                            .{ field.name, other.name },
                        );
                    }
                }
            }

            next_switch: for (arg[1..], 1..) |char, i| {
                inline for (fields) |field| {
                    if (char == @field(Flags.switches, field.name)) {
                        @field(passed, field.name) = true;

                        const FieldType = @TypeOf(@field(flags, field.name));
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (FieldType != bool and i != arg.len - 1) {
                            fatal("expected argument after switch '{c}'", .{char});
                        }
                        const value = parseArg(FieldType, args, &.{ '-', char });
                        @field(flags, field.name) = value;

                        continue :next_switch;
                    }
                }
                fatal("unrecognized switch: {c}", .{char});
            }
        }
        continue :next_arg;
    }

    inline for (std.meta.fields(Flags)) |field| if (!@field(passed, field.name)) {
        if (field.default_value) |default_opaque| {
            const default = @as(*const field.type, @ptrCast(@alignCast(default_opaque))).*;
            @field(flags, field.name) = default;
        } else {
            @field(flags, field.name) = switch (@typeInfo(field.type)) {
                .Optional => null,
                .Bool => false,
                else => fatal("missing required flag: '{s}'", .{format.flagName(field)}),
            };
        }
    };

    return flags;
}

fn parseArg(comptime T: type, args: *ArgIterator, flag_name: []const u8) T {
    if (T == bool) return true;

    const value = args.next() orelse fatal("expected argument for '{s}'", .{flag_name});

    const V = switch (@typeInfo(T)) {
        .Optional => |optional| optional.child,
        else => T,
    };

    if (V == []const u8) return value;

    if (@typeInfo(V) == .Enum) {
        inline for (std.meta.fields(V)) |field| {
            if (std.mem.eql(u8, value, format.toKebab(field.name))) {
                return @field(V, field.name);
            }
        }

        fatal("invalid option for '{s}': '{s}'", .{ flag_name, value });
    }

    if (@typeInfo(V) == .Int) {
        const num = std.fmt.parseInt(V, value, 10) catch |err| switch (err) {
            error.Overflow => fatal(
                "integer argument too big for {s}: '{s}'",
                .{ @typeName(V), value },
            ),
            error.InvalidCharacter => fatal(
                "expected integer argument for '{s}', found '{s}'",
                .{ flag_name, value },
            ),
        };
        return num;
    }

    compileError("invalid flag type: {s}", .{@typeName(T)});
}
