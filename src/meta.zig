const std = @import("std");

pub const FlagsInfo = struct {
    flags: []const Flag = &.{},
    positionals: []const Positional = &.{},
    subcommands: []const SubCommand = &.{},
};

const SubCommand = struct {
    /// A nested Flags struct.
    type: type,
    field_name: []const u8,
    command_name: []const u8,
};

pub const Flag = struct {
    type: type,
    default_value: ?*const anyopaque,
    field_name: []const u8,
    /// For field_name == "my_flag" -> flag_name == "--my-flag".
    flag_name: []const u8,
    switch_char: ?u8,
};

pub const Positional = struct {
    type: type,
    default_value: ?*const anyopaque,
    field_name: []const u8,
    /// The placeholder name, e.g `<FILE>`
    arg_name: []const u8,
};

pub fn info(comptime Flags: type) FlagsInfo {
    std.debug.assert(@inComptime());
    if (@typeInfo(Flags) != .@"struct") {
        compileError("input type is not a struct: {s}", .{@typeName(Flags)});
    }

    var command = FlagsInfo{};

    var switches: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), ?u8, @as(?u8, null)) = .{};
    if (@hasDecl(Flags, "switches")) {
        const Switches = @TypeOf(Flags.switches);
        if (@typeInfo(Switches) != .@"struct") compileError(
            "switches is not a struct value: {s}",
            .{@typeName(Switches)},
        );

        const switch_fields = @typeInfo(Switches).@"struct".fields;
        for (switch_fields, 0..) |switch_field, field_index| {
            if (!@hasField(Flags, switch_field.name)) {
                compileError("switch name does not match any field: {s}", .{switch_field.name});
            }

            const switch_val = @field(Flags.switches, switch_field.name);
            if (@TypeOf(switch_val) != comptime_int) {
                compileError("switch value is not a character: {any}", .{switch_val});
            }
            const switch_char = std.math.cast(u8, switch_val) orelse {
                compileError("switch value is not a character: {any}", .{switch_val});
            };
            if (!std.ascii.isAlphanumeric(switch_char)) {
                compileError("switch character is not a letter or digit: {c}", .{switch_char});
            }

            for (switch_fields[field_index + 1 ..]) |other_field| {
                const other_val = @field(Flags.switches, other_field.name);
                if (switch_val == other_val) compileError(
                    "duplicate switch values: {s} and {s}",
                    .{ switch_field.name, other_field.name },
                );
            }

            @field(switches, switch_field.name) = switch_char;
        }
    }

    for (@typeInfo(Flags).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "positional")) {
            if (@typeInfo(field.type) != .@"struct") compileError(
                "'positional' field is not a struct type: {s}",
                .{@typeName(field.type)},
            );

            var seen_optional = false;
            for (@typeInfo(field.type).@"struct".fields) |positional| {
                if (@typeInfo(positional.type) != .optional) {
                    if (seen_optional) compileError(
                        "non-optional positional field after optional: {s}",
                        .{positional.name},
                    );
                } else {
                    seen_optional = true;
                }
                command.positionals = command.positionals ++ .{Positional{
                    .type = positional.type,
                    .default_value = positional.default_value,
                    .field_name = positional.name,
                    .arg_name = positionalName(positional),
                }};
            }
        } else if (std.mem.eql(u8, field.name, "command")) {
            if (@typeInfo(field.type) != .@"union") compileError(
                "command field type is not a union: {s}",
                .{@typeName(field.type)},
            );

            for (@typeInfo(field.type).@"union".fields) |cmd| {
                command.subcommands = command.subcommands ++ .{SubCommand{
                    .type = cmd.type,
                    .field_name = cmd.name,
                    .command_name = toKebab(cmd.name),
                }};
            }
        } else {
            command.flags = command.flags ++ .{Flag{
                .type = field.type,
                .default_value = field.default_value,
                .field_name = field.name,
                .flag_name = "--" ++ toKebab(field.name),
                .switch_char = @field(switches, field.name),
            }};
        }
    }

    return command;
}

pub fn compileError(comptime fmt: []const u8, args: anytype) void {
    @compileError("(flags) " ++ std.fmt.comptimePrint(fmt, args));
}

pub fn unwrapOptional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |opt| opt.child,
        else => T,
    };
}

/// Casts the opaque default_value, if it exists, to a Flag/Positional's actual type.
pub fn defaultValue(comptime option: anytype) ?option.type {
    const default_opaque = option.default_value orelse return null;
    const default: *const option.type = @ptrCast(@alignCast(default_opaque));
    return default.*;
}

/// Converts "positional_field" to "<POSITIONAL_FIELD>.".
pub fn positionalName(comptime field: std.builtin.Type.StructField) []const u8 {
    comptime var upper: []const u8 = &.{};
    comptime for (field.name) |c| {
        upper = upper ++ .{std.ascii.toUpper(c)};
    };
    return std.fmt.comptimePrint("<{s}>", .{upper});
}

/// Converts from snake_case to kebab-case at comptime.
pub fn toKebab(comptime string: []const u8) []const u8 {
    comptime var name: []const u8 = "";

    inline for (string) |ch| name = name ++ .{switch (ch) {
        '_' => '-',
        else => ch,
    }};

    return name;
}
