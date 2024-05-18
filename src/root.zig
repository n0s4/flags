const std = @import("std");
const root = @import("root");
const validate = @import("validate.zig");

const ArgIterator = std.process.ArgIterator;

/// Combines `Config` with an `args` field which stores positional arguments.
pub fn Result(comptime Config: type) type {
    return struct {
        config: Config,
        /// Stores extra positional arguments not linked to any flag or option.
        args: []const []const u8,
    };
}

/// Prints the formatted error message to stderr and exits with status code 1.
pub fn fatal(comptime message: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("error: " ++ message ++ ".\n", args) catch {};
    std.process.exit(1);
}

const default_max_positionals = 32;
const max_positional_args: comptime_int = if (@hasDecl(root, "max_positional_arguments"))
    root.max_positional_arguments
else
    default_max_positionals;
// This must be global to guarantee a static lifetime, otherwise allocation would be needed at
// runtime to store positional arguments.
var positionals: [max_positional_args][]const u8 = undefined;

pub fn parse(args: *ArgIterator, comptime Command: type) Result(Command) {
    std.debug.assert(args.skip());
    return parseGeneric(args, Command);
}

fn parseGeneric(args: *ArgIterator, comptime Command: type) Result(Command) {
    return switch (@typeInfo(Command)) {
        .Union => parseCommands(args, Command),
        .Struct => parseOptions(args, Command),
        else => @compileError("Command must be a struct or union type."),
    };
}

fn parseCommands(args: *ArgIterator, comptime Commands: type) Result(Commands) {
    const sub_command = args.next() orelse fatal("expected subcommand", .{});

    inline for (@typeInfo(Commands).Union.fields) |command| {
        if (std.mem.eql(u8, command.name, sub_command)) {
            const sub_result = parseGeneric(args, command.type);
            return .{
                .config = @unionInit(Commands, command.name, sub_result.config),
                .args = sub_result.args,
            };
        }
    }

    fatal("unrecognized subcommand: '{s}'", .{sub_command});
}

fn parseOptions(args: *ArgIterator, comptime Options: type) Result(Options) {
    comptime validate.assertValidConfig(Options);
    var options: Options = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Options), bool, false) = .{};

    var positional_count: u32 = 0;

    next_arg: while (args.next()) |arg| {
        if (arg.len == 0) fatal("empty argument", .{});

        if (arg[0] != '-') {
            if (positional_count == max_positional_args) fatal("too many arguments", .{});
            positionals[positional_count] = arg;
            positional_count += 1;

            continue :next_arg;
        }

        if (arg.len == 1) fatal("unrecognized argument: '-'", .{});
        if (arg[1] == '-') {
            inline for (std.meta.fields(Options)) |field| {
                if (std.mem.eql(u8, arg, flagName(field))) {
                    @field(passed, field.name) = true;

                    @field(options, field.name) = parseArg(field.type, args, flagName(field));

                    continue :next_arg;
                }
            }
            fatal("unrecognized flag: {s}", .{arg});
        }

        if (@hasDecl(Options, "switches")) {
            next_switch: for (arg[1..], 1..) |char, i| {
                inline for (std.meta.fields(@TypeOf(Options.switches))) |switch_field| {
                    if (char == @field(Options.switches, switch_field.name)) {
                        @field(passed, switch_field.name) = true;

                        const FieldType = @TypeOf(@field(options, switch_field.name));
                        // Removing this check would allow formats like "-abc value-for-a value-for-b value-for-c"
                        if (FieldType != bool and i != arg.len - 1) {
                            fatal("expected argument after switch '{c}'", .{char});
                        }
                        const value = parseArg(FieldType, args, &.{ '-', char });
                        @field(options, switch_field.name) = value;

                        continue :next_switch;
                    }
                }

                fatal("unrecognized switch: {c}", .{char});
            }
            continue :next_arg;
        }
    }

    inline for (std.meta.fields(Options)) |field| {
        if (@field(passed, field.name) == false) {
            if (field.default_value) |default_opaque| {
                const default = @as(*const field.type, @ptrCast(@alignCast(default_opaque))).*;
                @field(options, field.name) = default;
            } else {
                @field(options, field.name) = switch (@typeInfo(field.type)) {
                    .Optional => null,
                    .Bool => false,
                    else => fatal("missing required flag: '{s}'", .{flagName(field)}),
                };
            }
        }
    }

    return Result(Options){
        .config = options,
        .args = positionals[0..positional_count],
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
            if (std.mem.eql(u8, value, toKebab(field.name))) {
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

/// Converts `my_zig_field` to `--my-zig-field` at comptime for comparison to command line flags.
fn flagName(comptime field: std.builtin.Type.StructField) []const u8 {
    return "--" ++ comptime toKebab(field.name);
}

/// Converts from snake_case to kebab-case at comptime.
fn toKebab(comptime string: []const u8) []const u8 {
    return comptime blk: {
        var name: []const u8 = "";

        for (string) |ch| name = name ++ .{switch (ch) {
            '_' => '-',
            else => ch,
        }};

        break :blk name;
    };
}
