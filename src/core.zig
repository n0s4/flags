const std = @import("std");
const help = @import("help.zig");
const meta = @import("meta.zig");
const cons = @import("console.zig");

const compileError = meta.compileError;

const ArgIterator = std.process.ArgIterator;

const FlagsMeta = struct {
    flags: type,
    info: meta.FlagsInfo,
    name: []const u8,
};

pub const TrailingHandler = struct {
    context: *anyopaque,
    handleFn: *const fn (context: *anyopaque, arg: []const u8) anyerror!void,

    fn handle(self: TrailingHandler, arg: []const u8) anyerror!void {
        return self.handleFn(self.context, arg);
    }
};

fn PositionalParser(comptime positionals: []const meta.Positional) type {
    return struct {
        const Self = @This();

        positional_count: usize = 0,
        trailing_handler: TrailingHandler,

        pub fn init(trailing_handler: TrailingHandler) Self {
            return .{ .trailing_handler = trailing_handler };
        }

        fn parse(self: *Self, arg: []const u8, flags: anytype) anyerror!void {
            if (self.positional_count >= positionals.len) {
                return self.trailing_handler.handle(arg);
            }
            switch (self.positional_count) {
                inline 0...positionals.len - 1 => |i| {
                    self.positional_count += 1;
                    const pos = positionals[i];
                    const T = meta.unwrapOptional(pos.type);
                    @field(flags.positional, pos.field_name) = try parseValue(T, arg);
                },
                else => unreachable,
            }
        }
    };
}

/// Print an error message
pub fn printError(comptime fmt: []const u8, args: anytype) void {
    cons.printStyled(std.io.getStdOut().writer(), .{ .fg_color = .Red, .bold = true }, "\nError: ", .{});
    cons.printColor(std.io.getStdOut().writer(), .White, fmt, args);
    cons.printColor(std.io.getStdOut().writer(), .White, "\n", .{});
}

/// Prints the help (usage) message to stdout
pub fn printHelp(help_message: []const u8) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("\n{s}\n", .{help_message}) catch |err| {
        const e = cons.ansi ++ cons.fg_red ++ cons.text_bold ++ "ERROR: " ++ cons.ansi_end;
        std.debug.print(e ++ "Could not write help to stdout: {!}", .{err});
        std.process.exit(1);
    };
}

/// Prints the help (usage) message to stdout and exits with error code 1
pub fn printFatalError(comptime fmt: []const u8, args: anytype) noreturn {
    printError(fmt, args);
    std.process.exit(1);
}

/// Prints the help (usage) message to stdout and exits with success code 0
pub fn printHelpAndExit(help_message: []const u8) noreturn {
    printHelp(help_message);
    std.process.exit(0);
}

pub fn parse(
    args: *ArgIterator,
    comptime Flags: type,
    comptime command_seq: []const u8,
    comptime max_line_len: usize,
    trailing_handler: TrailingHandler,
) !Flags {
    const info = meta.info(Flags);
    const help_message: []const u8 = if (@hasDecl(Flags, "help"))
        Flags.help // must be a string
    else
        comptime help.generate(Flags, info, command_seq, max_line_len);

    // If we error out, print the help message
    errdefer printHelp(help_message);

    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    var positional_parser = PositionalParser(info.positionals).init(trailing_handler);

    next_arg: while (args.next()) |arg| {
        if (arg.len == 0) {
            printError("empty argument", .{});
            return error.EmptyArgument;
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelpAndExit(help_message);
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positionals.
            while (args.next()) |positional| {
                try positional_parser.parse(positional, &flags);
            }
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            inline for (info.flags) |flag| {
                if (std.mem.eql(u8, arg, flag.flag_name)) {
                    @field(flags, flag.field_name) = try parseOption(flag.type, args, flag.flag_name);
                    @field(passed, flag.field_name) = true;
                    continue :next_arg;
                }
            }
            printError("unrecognized flag: {s}", .{arg});
            return error.UnknownArgument;
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) {
                printError("unrecognized argument: '-'", .{});
                return error.UnknownArgument;
            }
            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            printError("expected argument after switch: {c}", .{switch_char});
                            return error.MissingArgumentValue;
                        }
                        @field(flags, flag.field_name) = try parseOption(
                            flag.type,
                            args,
                            &.{ '-', switch_char },
                        );
                        @field(passed, flag.field_name) = true;
                        continue :next_switch;
                    }
                };
                printError("unrecognized switch: {c}", .{ch});
                return error.UnknownArgument;
            }
            continue :next_arg;
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                const sub_result = try parse(
                    args,
                    cmd.type,
                    command_seq ++ " " ++ cmd.command_name,
                    max_line_len,
                    trailing_handler,
                );
                flags.command = @unionInit(
                    @TypeOf(flags.command),
                    cmd.field_name,
                    sub_result,
                );
                passed.command = true;
                continue :next_arg;
            }
        }

        try positional_parser.parse(arg, &flags);
    }

    inline for (info.flags) |flag| if (!@field(passed, flag.field_name)) {
        @field(flags, flag.field_name) = meta.defaultValue(flag) orelse
            switch (@typeInfo(flag.type)) {
            .Bool => false,
            .Optional => null,
            else => {
                printError("missing required flag: {s}", .{flag.flag_name});
                return error.MissingRequiredFlag;
            },
        };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= positional_parser.positional_count) {
            @field(flags.positional, pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                .Optional => null,
                else => {
                    printError("missing required argument: {s}", .{pos.arg_name});
                    return error.MissingRequiredPositional;
                },
            };
        }
    }

    if (info.subcommands.len > 0 and !passed.command) {
        printError("expected subcommand", .{});
        return error.MissingRequiredCommand;
    }

    return flags;
}

/// Used for parsing both flags and switches.
fn parseOption(comptime T: type, args: *ArgIterator, comptime opt_name: []const u8) !T {
    if (T == bool) return true;

    const value = args.next() orelse {
        printError("expected value for '{s}'", .{opt_name});
        return error.MissingArgumentValue;
    };
    return try parseValue(meta.unwrapOptional(T), value);
}

fn parseValue(comptime T: type, arg: []const u8) !T {
    if (T == []const u8) return arg;
    switch (@typeInfo(T)) {
        .Int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| switch (err) {
            error.Overflow => {
                printFatalError("value out of bounds for {d}-bit {s} integer: '{s}'", .{ info.bits, @tagName(info.signedness), arg });
                return error.IntegerDataType;
            },
            error.InvalidCharacter => {
                printFatalError("expected integer value, found '{s}'", .{arg});
                return error.InvalidDataType;
            },
        },
        .Float => return std.fmt.parseFloat(T, arg) catch |err| switch (err) {
            error.InvalidCharacter => {
                printFatalError("expected floating-point number, found '{s}'", .{arg});
                return error.InvalidDataType;
            },
        },
        .Enum => {
            inline for (std.meta.fields(T)) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }
            printError("invalid option: '{s}'", .{arg});
            return error.InvalidOption;
        },

        else => comptime compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}
