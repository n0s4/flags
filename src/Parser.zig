const Parser = @This();

const std = @import("std");
const meta = @import("meta.zig");
const help = @import("help.zig");

const ArgIterator = std.process.ArgIterator;
const AnyWriter = std.io.AnyWriter;

pub const Error = error{
    /// Some argument contained no characters.
    EmptyArgument,
    /// -h or --help was passed and the help message was printed instead of parsing.
    PrintedHelp,
    /// Failed to print help message to stdout.
    StdoutError,
    /// One too many positional arguments were passed.
    UnexpectedPositional,
    /// An argument beginning with '--' did not match any flag name.
    UnrecognizedFlag,
    /// A flag which expects a value was passed without a value.
    MissingValue,
    /// A value which was passed for an enum option did not match any variants.
    InvalidOption,
    /// A required flag was not passed.
    MissingFlag,
    /// A required positional argument was not passed.
    MissingArgument,
    /// A subcommand was expected but not passed.
    MissingCommand,
} || std.fmt.ParseIntError || std.fmt.ParseFloatError;

/// Carries the name, usage and help message of the command in which the parsing error occured.
pub const ErrorInfo = struct {
    command_name: []const u8,
    command_usage: []const u8,
    command_help: []const u8,
};

args: *ArgIterator,
positional_count: usize,
stderr: AnyWriter,
stdout: AnyWriter,
error_info: ?*ErrorInfo,

pub const InitOptions = struct {
    /// std.io.getStdErr() will be used by default.
    stderr: ?AnyWriter = null,
    /// std.io.getStdOut() will be used by default.
    stdout: ?AnyWriter = null,
    /// The first argument is typically the name of the executable.
    skip_first_arg: bool = true,
    /// Carries optional extra information about the command in which an error occured.
    /// Pass this if you want to print relevant usage after an error.
    error_info: ?*ErrorInfo = null,
};

pub fn init(args: *ArgIterator, options: InitOptions) Parser {
    if (options.skip_first_arg) _ = args.skip();

    return Parser{
        .args = args,
        .positional_count = 0,
        .stdout = options.stdout orelse std.io.getStdOut().writer().any(),
        .stderr = options.stderr orelse std.io.getStdErr().writer().any(),
        .error_info = options.error_info,
    };
}

pub fn parseOrExit(
    parser: *Parser,
    comptime command_name: []const u8,
    comptime Flags: type,
) Flags {
    return parser.parse(command_name, Flags) catch |err| std.posix.exit(switch (err) {
        error.PrintedHelp => 0,
        else => 1,
    });
}

pub fn parse(parser: *Parser, comptime command_name: []const u8, comptime Flags: type) Error!Flags {
    const info = meta.info(Flags);

    const help_message: []const u8 = if (@hasDecl(Flags, "help"))
        Flags.help // must be a string
    else
        comptime help.generate(Flags, info, command_name);

    if (parser.error_info) |error_info| {
        error_info.command_name = command_name;
        error_info.command_help = help_message;
        // error_info.command_usage =
    }

    var flags: Flags = undefined;

    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    next_arg: while (parser.args.next()) |arg| {
        if (arg.len == 0) {
            parser.report("empty argument", .{});
            return Error.EmptyArgument;
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parser.stdout.writeAll(help_message) catch return Error.StdoutError;
            return Error.PrintedHelp;
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positionals.
            while (parser.args.next()) |positional| {
                try parser.parsePositional(positional, info.positionals, &flags);
            }
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            inline for (info.flags) |flag| if (std.mem.eql(u8, arg, flag.flag_name)) {
                @field(flags, flag.field_name) = try parser.parseOption(flag.type, flag.flag_name);
                @field(passed, flag.field_name) = true;
                continue :next_arg;
            };

            parser.report("unrecognized flag: {s}", .{arg});
            return Error.UnrecognizedFlag;
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) parser.report("unrecognized argument: '-'", .{});
            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            parser.report("expected argument after switch: {c}", .{switch_char});
                        }
                        @field(flags, flag.field_name) = try parser.parseOption(
                            flag.type,
                            &.{ '-', switch_char },
                        );
                        @field(passed, flag.field_name) = true;
                        continue :next_switch;
                    }
                };
                parser.report("unrecognized switch: {c}", .{ch});
            }
            continue :next_arg;
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                const cmd_flags = try parser.parse(
                    command_name ++ " " ++ cmd.command_name,
                    cmd.type,
                );
                flags.command = @unionInit(@TypeOf(flags.command), cmd.field_name, cmd_flags);
                passed.command = true;
                continue :next_arg;
            }
        }

        try parser.parsePositional(arg, info.positionals, &flags);
    }

    inline for (info.flags) |flag| if (!@field(passed, flag.field_name)) {
        @field(flags, flag.field_name) = meta.defaultValue(flag) orelse
            switch (@typeInfo(flag.type)) {
            .bool => false,
            .optional => null,
            else => {
                parser.report("missing required flag: {s}", .{flag.flag_name});
                return Error.MissingFlag;
            },
        };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= parser.positional_count) {
            @field(flags.positional, pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                .optional => null,
                else => {
                    parser.report("missing required argument: {s}", .{pos.arg_name});
                    return Error.MissingArgument;
                },
            };
        }
    }

    if (info.subcommands.len > 0 and !passed.command) {
        parser.report("expected subcommand", .{});
        return Error.MissingCommand;
    }

    return flags;
}

fn parsePositional(
    parser: *Parser,
    arg: []const u8,
    positionals: []const meta.Positional,
    flags: anytype,
) Error!void {
    if (parser.positional_count >= positionals.len) {
        parser.report("unexpected argument: {s}", .{arg});
        return Error.UnexpectedPositional;
    }

    switch (parser.positional_count) {
        inline 0...positionals.len - 1 => |i| {
            parser.positional_count += 1;
            const positional = positionals[i];
            const T = meta.unwrapOptional(positional.type);
            @field(flags.positional, positional.field_name) = try parser.parseValue(T, arg);
        },
        else => unreachable,
    }
}

fn parseOption(parser: Parser, comptime T: type, comptime option_name: []const u8) Error!T {
    if (T == bool) return true;

    const value = parser.args.next() orelse {
        parser.report("missing value for '{s}'", .{option_name});
        return Error.MissingValue;
    };

    return try parser.parseValue(meta.unwrapOptional(T), value);
}

fn parseValue(parser: Parser, comptime T: type, arg: []const u8) Error!T {
    if (T == []const u8) return arg;

    switch (@typeInfo(T)) {
        .int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| {
            switch (err) {
                error.Overflow => parser.report(
                    "value out of bounds for {d}-bit {s} integer: {s}",
                    .{ info.bits, @tagName(info.signedness), arg },
                ),
                error.InvalidCharacter => parser.report(
                    "expected integer number, found '{s}'",
                    .{arg},
                ),
            }
            return err;
        },

        .float => return std.fmt.parseFloat(T, arg) catch |err| {
            switch (err) {
                error.InvalidCharacter => parser.report("expected numerical value, found '{s}'", .{arg}),
            }
            return err;
        },

        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }

            parser.report("invalid option: {s}", .{arg});
            return Error.InvalidOption;
        },

        else => comptime meta.compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}

fn report(parser: Parser, comptime fmt: []const u8, args: anytype) void {
    parser.stderr.print("error: " ++ fmt ++ "\n", args) catch {};
}
