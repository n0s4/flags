const std = @import("std");
const validate = @import("validate.zig");
const help = @import("help.zig");
const format = @import("format.zig");

const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;

/// Prints the formatted error message to stderr and exits with status code 1.
pub fn fatal(comptime message: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("error: " ++ message ++ ".\n", args) catch {};
    std.process.exit(1);
}

fn printHelp(comptime Command: type, comptime command_name: []const u8) noreturn {
    const message = comptime help.helpMessage(Command, command_name);

    std.io.getStdOut().writeAll(message) catch |err| {
        fatal("could not write help to stdout: {!}", .{err});
    };

    std.process.exit(0);
}

const PositionalList = struct {
    buffer: std.ArrayListUnmanaged([]const u8),

    pub fn init(buffer: [][]const u8) PositionalList {
        return .{
            .buffer = std.ArrayListUnmanaged([]const u8).initBuffer(buffer),
        };
    }

    pub fn append(self: *PositionalList, positional: []const u8) Allocator.Error!void {
        if (self.buffer.items.len >= self.buffer.capacity) {
            return Allocator.Error.OutOfMemory;
        }
        self.buffer.appendAssumeCapacity(positional);
    }
};

pub const ParseOptions = struct {
    /// The first argument is almost always the executable name used to run the program.
    skip_first_arg: bool = true,

    /// Give useful compile errors if your `Command` type is invalid.
    ///
    /// Only disable if you don't need help and want to save the compiler from unnecessary work.
    validate: bool = true,
};

/// Combines `Command` with an `args` field which stores positional arguments.
fn Result(comptime Command: type) type {
    return struct {
        flags: Command,
        /// Stores extra positional arguments not linked to any flag.
        args: []const []const u8,
    };
}

/// This does not allow any positional arguments to be passed.
///
/// If you need to take positional arguments, use `parseWithBuffer`.
pub fn parse(args: *ArgIterator, comptime Command: type, comptime options: ParseOptions) Command {
    // Using an empty buffer means that any positional argument will case an error.
    var empty = [0][]const u8{};
    const result = parseWithBuffer(&empty, args, Command, options) catch {
        fatal("unexpected stray argument", .{});
    };

    return result.flags;
}

/// Uses a fixed buffer to store positional/trailing arguments.
/// Fails if the number of positional arguments passed cannot fit in the buffer.
pub fn parseWithBuffer(
    positional_args_buf: [][]const u8,
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) Allocator.Error!Result(Command) {
    if (options.validate) {
        comptime validate.assertValid(Command);
    }
    if (options.skip_first_arg) {
        if (!args.skip()) fatal("expected at least 1 argument", .{});
    }

    var positionals = PositionalList.init(positional_args_buf);
    return parseGeneric(args, &positionals, Command, Command.name);
}

/// The "main" parsing function.
fn parseGeneric(
    args: *ArgIterator,
    positionals: *PositionalList,
    comptime Command: type,
    comptime command_name: []const u8,
) Allocator.Error!Result(Command) {
    return switch (@typeInfo(Command)) {
        .Union => parseCommands(args, positionals, Command, command_name),
        .Struct => parseFlags(args, positionals, Command, command_name),
        else => comptime unreachable,
    };
}

fn parseCommands(
    args: *ArgIterator,
    positionals: *PositionalList,
    comptime Commands: type,
    comptime command_name: []const u8,
) Allocator.Error!Result(Commands) {
    const arg = args.next() orelse fatal("expected subcommand", .{});

    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        printHelp(Commands, command_name);
    }

    inline for (@typeInfo(Commands).Union.fields) |command| {
        if (std.mem.eql(u8, comptime format.toKebab(command.name), arg)) {
            const sub_result = try parseGeneric(
                args,
                positionals,
                command.type,
                command_name ++ " " ++ command.name,
            );

            return .{
                .flags = @unionInit(Commands, command.name, sub_result.flags),
                .args = sub_result.args,
            };
        }
    }

    fatal("unrecognized subcommand: '{s}'. see {s} --help", .{ arg, command_name });
}

fn parseFlags(
    args: *ArgIterator,
    positionals: *PositionalList,
    comptime Flags: type,
    comptime command_name: []const u8,
) Allocator.Error!Result(Flags) {
    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    next_arg: while (args.next()) |arg| {
        if (arg.len == 0) fatal("empty argument", .{});

        if (arg[0] != '-') {
            try positionals.append(arg);
            continue :next_arg;
        }

        if (arg.len == 1) fatal("unrecognized argument: '-'", .{});

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat the remaining flags as positional arguments
            while (args.next()) |positional| {
                try positionals.append(positional);
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

    return Result(Flags){
        .flags = flags,
        .args = positionals.buffer.items,
    };
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
