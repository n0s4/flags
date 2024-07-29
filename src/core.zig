const std = @import("std");
const format = @import("format.zig");
const help = @import("help.zig");
const meta = @import("meta.zig");
const validate = @import("validate.zig");

const compileError = meta.compileError;

const ArgIterator = std.process.ArgIterator;

pub const TrailingHandler = struct {
    context: *anyopaque,
    handleFn: *const fn (context: *anyopaque, arg: []const u8) anyerror!void,

    fn handle(self: TrailingHandler, arg: []const u8) anyerror!void {
        return self.handleFn(self.context, arg);
    }
};

fn PositionalParser(comptime Flags: type) type {
    return struct {
        const Self = @This();

        const positional_fields: []const std.builtin.Type.StructField = blk: {
            if (@hasField(Flags, "positional")) {
                const Positional = std.meta.FieldType(Flags, .positional);
                validate.validatePositionals(Positional);
                break :blk @typeInfo(Positional).Struct.fields;
            } else {
                break :blk &.{};
            }
        };

        positional_count: usize = 0,
        trailing_handler: TrailingHandler,

        pub fn init(trailing_handler: TrailingHandler) Self {
            return .{ .trailing_handler = trailing_handler };
        }

        fn parse(self: *Self, arg: []const u8, flags: *Flags) anyerror!void {
            if (self.positional_count >= positional_fields.len) {
                return self.trailing_handler.handle(arg);
            }
            switch (self.positional_count) {
                inline 0...positional_fields.len - 1 => |i| {
                    self.positional_count += 1;
                    const field = positional_fields[i];
                    const T = meta.unwrapOptional(field.type);
                    @field(flags.positional, field.name) = parseValue(T, arg);
                },
                else => unreachable,
            }
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
        if (!meta.isString(@TypeOf(Command.full_help))) {
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
    trailing_handler: TrailingHandler,
) !Command {
    return switch (@typeInfo(Command)) {
        .Union => parseCommands(args, Command, command_name, trailing_handler),
        .Struct => parseFlags(args, Command, command_name, trailing_handler),
        else => comptime unreachable,
    };
}

fn parseCommands(
    args: *ArgIterator,
    comptime Commands: type,
    comptime command_name: []const u8,
    trailing_handler: TrailingHandler,
) !Commands {
    const arg = args.next() orelse fatal("expected subcommand", .{});

    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        printHelp(Commands, command_name);
    }

    inline for (std.meta.fields(Commands)) |command| {
        if (std.mem.eql(u8, comptime format.toKebab(command.name), arg)) {
            const sub_result = try parse(
                args,
                command.type,
                command_name ++ " " ++ format.toKebab(command.name),
                trailing_handler,
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
    trailing_handler: TrailingHandler,
) !Flags {
    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    const flag_fields = comptime blk: {
        var fields: []const std.builtin.Type.StructField = &.{};
        for (std.meta.fields(Flags)) |field| {
            if (!std.mem.eql(u8, field.name, "positional")) {
                fields = fields ++ &[1]std.builtin.Type.StructField{field};
            }
        }
        break :blk fields;
    };

    var positional_parser = PositionalParser(Flags).init(trailing_handler);

    next_arg: while (args.next()) |arg| {
        if (arg.len == 0) fatal("empty argument", .{});

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp(Flags, command_name);
            continue :next_arg;
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positionals.
            while (args.next()) |positional| {
                try positional_parser.parse(positional, &flags);
            }
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            inline for (flag_fields) |field| {
                comptime if (std.mem.eql(u8, field.name, "help")) {
                    compileError("flag name 'help' is reserved for showing help", .{});
                };

                if (std.mem.eql(u8, arg, format.flagName(field))) {
                    @field(passed, field.name) = true;

                    @field(flags, field.name) =
                        parseFlag(field.type, args, format.flagName(field));

                    continue :next_arg;
                }
            }
            fatal("unrecognized flag: {s}", .{arg});
        }

        if (@hasDecl(Flags, "switches") and arg[0] == '-') {
            const Switches = @TypeOf(Flags.switches);
            comptime validate.validateSwitches(Flags, Switches);

            next_switch: for (arg[1..], 1..) |char, i| {
                if (char == 'h') printHelp(Flags, command_name);
                inline for (@typeInfo(Switches).Struct.fields) |field| {
                    if (char == @field(Flags.switches, field.name)) {
                        std.log.debug("dbg", .{});
                        @field(passed, field.name) = true;

                        const FieldType = @TypeOf(@field(flags, field.name));
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (FieldType != bool and i != arg.len - 1) {
                            fatal("expected argument after switch '{c}'", .{char});
                        }
                        const value = parseFlag(FieldType, args, &.{ '-', char });
                        @field(flags, field.name) = value;

                        continue :next_switch;
                    }
                }
                fatal("unrecognized switch: {c}", .{char});
            }
            continue :next_arg;
        }

        try positional_parser.parse(arg, &flags);
    }

    inline for (flag_fields) |field| if (!@field(passed, field.name)) {
        @field(flags, field.name) = meta.defaultValue(field) orelse switch (@typeInfo(field.type)) {
            .Optional => null,
            .Bool => false,
            else => fatal("missing required flag: '{s}'", .{format.flagName(field)}),
        };
    };

    if (@hasField(Flags, "positional")) {
        const fields = std.meta.fields(@TypeOf(flags.positional));
        inline for (fields, 0..) |field, field_idx| {
            if (field_idx >= positional_parser.positional_count) {
                @field(flags.positional, field.name) = meta.defaultValue(field) orelse
                    switch (@typeInfo(field.type)) {
                    .Optional => null,
                    else => fatal("missing required argument: {s}", .{format.positionalName(field)}),
                };
            }
        }
    }

    return flags;
}

fn parseFlag(comptime T: type, args: *ArgIterator, flag_name: []const u8) T {
    if (T == bool) return true;

    const value = args.next() orelse fatal("expected value for '{s}'", .{flag_name});
    return parseValue(meta.unwrapOptional(T), value);
}

fn parseValue(comptime T: type, arg: []const u8) T {
    if (T == []const u8) return arg;
    switch (@typeInfo(T)) {
        .Int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| switch (err) {
            error.Overflow => fatal(
                "value out of bounds for {d}-bit {s} integer: '{s}'",
                .{ info.bits, @tagName(info.signedness), arg },
            ),
            error.InvalidCharacter => fatal("expected integer value, found '{s}'", .{arg}),
        },
        .Float => return std.fmt.parseFloat(T, arg) catch |err| switch (err) {
            error.InvalidCharacter => fatal("expected floating-point number, found '{s}'", .{arg}),
        },
        .Enum => {
            inline for (std.meta.fields(T)) |field| {
                if (std.mem.eql(u8, arg, format.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }
            fatal("invalid option: '{s}'", .{arg});
        },

        else => comptime compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}
