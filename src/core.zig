const std = @import("std");
const help = @import("help.zig");
const meta = @import("meta.zig");

const compileError = meta.compileError;

const ArgIterator = std.process.ArgIterator;

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
                    @field(flags.positional, pos.field_name) = parseValue(T, arg);
                },
                else => unreachable,
            }
        }
    };
}

/// Prints the formatted error message to stderr and exits with status code 1.
pub fn fatal(comptime message: []const u8, args: anytype) noreturn {
    std.io.getStdErr().writer()
        .print("error: " ++ message ++ ".\n", args) catch {};
    std.process.exit(1);
}

pub fn printHelp(help_message: []const u8) noreturn {
    std.io.getStdOut().writeAll(help_message) catch |err| {
        fatal("could not write help to stdout: {!}", .{err});
    };

    std.process.exit(0);
}

pub fn parse(
    args: *ArgIterator,
    comptime Flags: type,
    comptime command_seq: []const u8,
    trailing_handler: TrailingHandler,
) !Flags {
    const info = meta.info(Flags);
    const help_message: []const u8 = if (@hasDecl(Flags, "help"))
        Flags.help // must be a string
    else
        comptime help.generate(Flags, info, command_seq);

    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    var positional_parser = PositionalParser(info.positionals).init(trailing_handler);

    next_arg: while (args.next()) |arg| {
        if (arg.len == 0) fatal("empty argument", .{});

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp(help_message);
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
                    @field(flags, flag.field_name) = parseOption(flag.type, args, flag.flag_name);
                    @field(passed, flag.field_name) = true;
                    continue :next_arg;
                }
            }
            fatal("unrecognized flag: {s}", .{arg});
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) fatal("unrecognized argument: '-'", .{});
            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            fatal("expected argument after switch: {c}", .{switch_char});
                        }
                        @field(flags, flag.field_name) = parseOption(
                            flag.type,
                            args,
                            &.{ '-', switch_char },
                        );
                        @field(passed, flag.field_name) = true;
                        continue :next_switch;
                    }
                };
                fatal("unrecognized switch: {c}", .{ch});
            }
            continue :next_arg;
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                const sub_result = try parse(
                    args,
                    cmd.type,
                    command_seq ++ " " ++ cmd.command_name,
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
            .bool => false,
            .optional => null,
            else => fatal("missing required flag: {s}", .{flag.flag_name}),
        };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= positional_parser.positional_count) {
            @field(flags.positional, pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                .optional => null,
                else => fatal("missing required argument: {s}", .{pos.arg_name}),
            };
        }
    }

    if (info.subcommands.len > 0 and !passed.command) {
        fatal("expected subcommand", .{});
    }

    return flags;
}

/// Used for parsing both flags and switches.
fn parseOption(comptime T: type, args: *ArgIterator, comptime opt_name: []const u8) T {
    if (T == bool) return true;

    const value = args.next() orelse fatal("expected value for '{s}'", .{opt_name});
    return parseValue(meta.unwrapOptional(T), value);
}

fn parseValue(comptime T: type, arg: []const u8) T {
    if (T == []const u8) return arg;
    switch (@typeInfo(T)) {
        .int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| switch (err) {
            error.Overflow => fatal(
                "value out of bounds for {d}-bit {s} integer: '{s}'",
                .{ info.bits, @tagName(info.signedness), arg },
            ),
            error.InvalidCharacter => fatal("expected integer value, found '{s}'", .{arg}),
        },
        .float => return std.fmt.parseFloat(T, arg) catch |err| switch (err) {
            error.InvalidCharacter => fatal("expected floating-point number, found '{s}'", .{arg}),
        },
        .@"enum" => {
            inline for (std.meta.fields(T)) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }
            fatal("invalid option: '{s}'", .{arg});
        },

        else => comptime compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}
