const std = @import("std");
const format = @import("format.zig");
const help = @import("help.zig");

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
    const message = comptime help.helpMessage(Command, command_name);

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

    inline for (@typeInfo(Commands).Union.fields) |command| {
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
                if (std.mem.eql(u8, arg, format.flagName(field))) {
                    @field(passed, field.name) = true;

                    @field(flags, field.name) = parseArg(field.type, args, format.flagName(field));

                    continue :next_arg;
                }
            }
            fatal("unrecognized flag: {s}", .{arg});
        }

        if (@hasDecl(Flags, "switches")) {
            next_switch: for (arg[1..], 1..) |char, i| {
                inline for (std.meta.fields(@TypeOf(Flags.switches))) |switch_field| {
                    if (char == @field(Flags.switches, switch_field.name)) {
                        @field(passed, switch_field.name) = true;

                        const FieldType = @TypeOf(@field(flags, switch_field.name));
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (FieldType != bool and i != arg.len - 1) {
                            fatal("expected argument after switch '{c}'", .{char});
                        }
                        const value = parseArg(FieldType, args, &.{ '-', char });
                        @field(flags, switch_field.name) = value;

                        continue :next_switch;
                    }
                }

                fatal("unrecognized switch: {c}", .{char});
            }
            continue :next_arg;
        }
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

    comptime unreachable;
}
