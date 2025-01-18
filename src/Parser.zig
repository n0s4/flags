const Parser = @This();

const std = @import("std");
const meta = @import("meta.zig");

const root = @import("flags.zig");
const Diagnostics = root.Diagnostics;
const Options = root.Options;
const Error = root.Error;

pub const Help = @import("Help.zig");
pub const ColorScheme = @import("ColorScheme.zig");
pub const Terminal = @import("Terminal.zig");

args: []const [:0]const u8,
current_arg: usize,
colors: *const ColorScheme,
diagnostics: ?*Diagnostics,

fn report(parser: *const Parser, comptime fmt: []const u8, args: anytype) void {
    const stderr = Terminal.init(std.io.getStdErr());
    stderr.print(parser.colors.error_label, "Error: ", .{}) catch {};
    stderr.print(parser.colors.error_message, fmt ++ "\n", args) catch {};
}

pub fn parse(parser: *Parser, Flags: type, comptime command_name: []const u8) Error!Flags {
    const info = comptime meta.info(Flags);
    const help = comptime Help.generate(Flags, info, command_name);

    if (parser.diagnostics) |diags| {
        diags.command_name = command_name;
        diags.help = help;
    }

    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    // The index of the next positional field to be parsed.
    var positional_index: usize = 0;

    next_arg: while (parser.nextArg()) |arg| {
        if (arg.len == 0) {
            parser.report("empty argument", .{});
            return Error.EmptyArgument;
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try help.render(std.io.getStdOut(), parser.colors);
            return Error.PrintedHelp;
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positional.
            while (parser.nextArg()) |positional| {
                try parser.parsePositional(positional, positional_index, info.positionals, &flags);
                positional_index += 1;
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
            if (arg.len == 1) {
                parser.report("unrecognized argument: '-'", .{});
                return Error.UnrecognizedArgument;
            }

            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            parser.report("missing value after switch: {c}", .{switch_char});
                            return Error.MissingValue;
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
                return Error.UnrecognizedSwitch;
            }
            continue :next_arg;
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                const cmd_flags = try parser.parse(cmd.type, command_name ++ " " ++ cmd.command_name);
                flags.command = @unionInit(@TypeOf(flags.command), cmd.field_name, cmd_flags);
                passed.command = true;
                continue :next_arg;
            }
        }

        try parser.parsePositional(arg, positional_index, info.positionals, &flags);
        positional_index += 1;
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
        if (i >= positional_index) {
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
        parser.report("missing subcommand", .{});
        return Error.MissingCommand;
    }

    return flags;
}

fn parsePositional(
    parser: *Parser,
    arg: [:0]const u8,
    index: usize,
    comptime positionals: []const meta.Positional,
    flags: anytype,
) Error!void {
    if (index >= positionals.len) {
        parser.report("unexpected argument: {s}", .{arg});
        return error.UnexpectedPositional;
    }

    switch (index) {
        inline 0...positionals.len - 1 => |i| {
            const positional = positionals[i];
            const T = meta.unwrapOptional(positional.type);
            @field(flags.positional, positional.field_name) = try parser.parseValue(T, arg);
        },

        else => unreachable,
    }
}

fn parseOption(parser: *Parser, T: type, option_name: []const u8) Error!T {
    if (T == bool) return true;

    const value = parser.nextArg() orelse {
        parser.report("missing value for '{s}'", .{option_name});
        return Error.MissingValue;
    };

    return try parser.parseValue(meta.unwrapOptional(T), value);
}

fn parseValue(parser: *const Parser, T: type, arg: [:0]const u8) Error!T {
    if (T == []const u8 or T == [:0]const u8) return arg;

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

        .float => return std.fmt.parseFloat(T, arg) catch |err| switch (err) {
            error.InvalidCharacter => {
                parser.report("expected numerical value, found '{s}'", .{arg});
                return err;
            },
        },

        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }

            parser.report("unrecognized option: '{s}'", .{arg});
            return Error.UnrecognizedOption;
        },

        else => comptime meta.compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}

fn nextArg(parser: *Parser) ?[:0]const u8 {
    if (parser.current_arg >= parser.args.len) {
        return null;
    }

    parser.current_arg += 1;
    return parser.args[parser.current_arg - 1];
}
