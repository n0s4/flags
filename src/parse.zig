const std = @import("std");
const meta = @import("meta.zig");

const Help = @import("Help.zig");
const ColorScheme = @import("ColorScheme.zig");
const Terminal = @import("Terminal.zig");

const tty = std.io.tty;
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
    /// A switch character did not match any defined switch characters.
    UnrecognizedSwitch,
    /// Special case of user passing '-' without any switch characters.
    UnrecognizedArgument,
    /// A flag which expects a value was passed without a value.
    MissingValue,
    /// A value which was passed for an enum option did not match any variants.
    UnrecognizedOption,
    /// A required flag was not passed.
    MissingFlag,
    /// A required positional argument was not passed.
    MissingArgument,
    /// A subcommand was expected but not passed.
    MissingCommand,
} || std.fmt.ParseIntError || std.fmt.ParseFloatError;

pub const Diagnostics = struct {
    /// The full command name in which an error occured.
    command: []const u8,
    /// The help message for the command, whether custom or auto-generated.
    help: HelpImpl,
    /// The terminal that can be used for rendering a generated help message.
    /// Customised using the Options.stdout field, otherwise defaults to normal stdout.
    stdout: Terminal,
};

const HelpImpl = union(enum) {
    /// A custom help string for any command which has defined one via a declaration named "help".
    custom: []const u8,
    /// Generated help for commands which don't declare a custom "help" string.
    /// It can be printed using the `render` method to a `Terminal`.
    /// To print only usage, use the same method on the `usage` field of the struct.
    generated: Help,
};

/// Global state.
const Env = struct {
    args: *ArgIterator,
    stdout: Terminal,
    stderr: Terminal,
    diagnostics: ?*Diagnostics,
    colors: ColorScheme,
};

var env: Env = undefined;

fn report(comptime message: []const u8, args: anytype) void {
    env.stderr.print(env.colors.error_label, "Error: ", .{}) catch unreachable;
    env.stderr.print(env.colors.error_message, message ++ "\n", args) catch unreachable;
}

fn printHelp(comptime help: HelpImpl) Error!void {
    switch (help) {
        .custom => |h| {
            env.stdout.print(&.{}, h, .{}) catch unreachable;
        },
        .generated => |h| {
            h.render(env.stdout, env.colors) catch unreachable;
        },
    }
}

pub const Options = struct {
    /// Defaults to stdout.
    help_writer: ?AnyWriter = null,
    /// Defaults to stderr.
    error_writer: ?AnyWriter = null,
    /// Gives information about the command if a parsing error occurs.
    /// Used to print usage/help
    diagnostics: ?*Diagnostics = null,
    /// The first argument is normally the executable name.
    skip_first_arg: bool = true,
    /// Defines the colors used when printing help and error messages.
    /// To disable color, pass an empty colorscheme: `.colors = .{}`.
    colors: ColorScheme = ColorScheme.default,
};

pub fn parseOrExit(args: *ArgIterator, comptime exe_name: []const u8, Flags: type, options: Options) Flags {
    return parse(args, exe_name, Flags, options) catch |err| switch (err) {
        Error.PrintedHelp => std.process.exit(0),
        else => std.process.exit(1),
    };
}

pub fn parse(args: *ArgIterator, comptime exe_name: []const u8, Flags: type, options: Options) Error!Flags {
    if (options.skip_first_arg) _ = args.skip();

    env = Env{
        .args = args,
        .diagnostics = options.diagnostics,
        .colors = options.colors,

        .stdout = if (options.help_writer) |help_writer|
            Terminal.fromWriter(help_writer)
        else
            Terminal.fromFile(std.io.getStdOut()),

        .stderr = if (options.error_writer) |error_writer|
            Terminal.fromWriter(error_writer)
        else
            Terminal.fromFile(std.io.getStdErr()),
    };

    if (env.diagnostics) |diagnostics| {
        diagnostics.stdout = env.stdout;
    }
    return parse2(Flags, exe_name);
}

fn parse2(Flags: type, comptime command_name: []const u8) Error!Flags {
    const info = meta.info(Flags);

    const help: HelpImpl = if (@hasDecl(Flags, "help"))
        .{ .custom = Flags.help } // help must be a string
    else
        .{ .generated = comptime Help.generate(Flags, info, command_name) };

    if (env.diagnostics) |error_info| {
        error_info.* = .{
            .command = command_name,
            .help = help,
            .stdout = error_info.stdout,
        };
    }

    var flags: Flags = undefined;

    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    next_arg: while (env.args.next()) |arg| {
        if (arg.len == 0) {
            report("empty argument", .{});
            return Error.EmptyArgument;
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(help);
            return Error.PrintedHelp;
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positional.
            while (env.args.next()) |positional| {
                try parsePositional(positional, info.positionals, &flags);
            }
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            inline for (info.flags) |flag| if (std.mem.eql(u8, arg, flag.flag_name)) {
                @field(flags, flag.field_name) = try parseOption(flag.type, flag.flag_name);
                @field(passed, flag.field_name) = true;
                continue :next_arg;
            };

            report("unrecognized flag: {s}", .{arg});
            return Error.UnrecognizedFlag;
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) {
                report("unrecognized argument: '-'", .{});
                return Error.UnrecognizedArgument;
            }

            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            report("missing value after switch: {c}", .{switch_char});
                            return Error.MissingValue;
                        }
                        @field(flags, flag.field_name) = try parseOption(
                            flag.type,
                            &.{ '-', switch_char },
                        );
                        @field(passed, flag.field_name) = true;
                        continue :next_switch;
                    }
                };
                report("unrecognized switch: {c}", .{ch});
                return Error.UnrecognizedSwitch;
            }
            continue :next_arg;
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                const cmd_flags = try parse2(cmd.type, command_name ++ " " ++ cmd.command_name);
                flags.command = @unionInit(@TypeOf(flags.command), cmd.field_name, cmd_flags);
                passed.command = true;
                continue :next_arg;
            }
        }

        try parsePositional(arg, info.positionals, &flags);
    }

    inline for (info.flags) |flag| if (!@field(passed, flag.field_name)) {
        @field(flags, flag.field_name) = meta.defaultValue(flag) orelse
            switch (@typeInfo(flag.type)) {
            .bool => false,
            .optional => null,
            else => {
                report("missing required flag: {s}", .{flag.flag_name});
                return Error.MissingFlag;
            },
        };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= positional_count) {
            @field(flags.positional, pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                .optional => null,
                else => {
                    report("missing required argument: {s}", .{pos.arg_name});
                    return Error.MissingArgument;
                },
            };
        }
    }

    if (info.subcommands.len > 0 and !passed.command) {
        report("missing subcommand", .{});
        return Error.MissingCommand;
    }

    return flags;
}

var positional_count: usize = 0;

fn parsePositional(
    arg: []const u8,
    positionals: []const meta.Positional,
    flags: anytype,
) Error!void {
    if (positional_count >= positionals.len) {
        report("unexpected argument: {s}", .{arg});
        return Error.UnexpectedPositional;
    }

    switch (positional_count) {
        inline 0...positionals.len - 1 => |i| {
            positional_count += 1;
            const positional = positionals[i];
            const T = meta.unwrapOptional(positional.type);
            @field(flags.positional, positional.field_name) = try parseValue(T, arg);
        },
        else => unreachable,
    }
}

fn parseOption(T: type, option_name: []const u8) Error!T {
    if (T == bool) return true;

    const value = env.args.next() orelse {
        report("missing value for '{s}'", .{option_name});
        return Error.MissingValue;
    };

    return try parseValue(meta.unwrapOptional(T), value);
}

fn parseValue(T: type, arg: []const u8) Error!T {
    if (T == []const u8) return arg;

    switch (@typeInfo(T)) {
        .int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| {
            switch (err) {
                error.Overflow => report(
                    "value out of bounds for {d}-bit {s} integer: {s}",
                    .{ info.bits, @tagName(info.signedness), arg },
                ),
                error.InvalidCharacter => report(
                    "expected integer number, found '{s}'",
                    .{arg},
                ),
            }
            return err;
        },

        .float => return std.fmt.parseFloat(T, arg) catch |err| {
            switch (err) {
                error.InvalidCharacter => report("expected numerical value, found '{s}'", .{arg}),
            }
            return err;
        },

        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }

            report("unrecognized option: '{s}'", .{arg});
            return Error.UnrecognizedOption;
        },

        else => comptime meta.compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}
