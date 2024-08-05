const std = @import("std");
const meta = @import("meta.zig");
const compileError = meta.compileError;

pub fn validatePositionals(comptime Positional: type) void {
    std.debug.assert(@inComptime());
    const info = @typeInfo(Positional);
    if (info != .Struct) compileError(
        "expected 'positional' field to be a struct, found {s}",
        .{@typeName(Positional)},
    );
    var seen_optional = false;
    for (info.Struct.fields) |positional_field| {
        if (@typeInfo(positional_field.type) == .Optional) {
            seen_optional = true;
        } else {
            if (seen_optional) compileError(
                "found non-optional positional '{s}' after optional",
                .{positional_field.name},
            );
        }
    }
}

pub fn validateSwitches(comptime Flags: type, comptime Switches: type) void {
    std.debug.assert(@inComptime());
    if (@typeInfo(Switches) != .Struct) {
        compileError("'switches' is not a struct", .{});
    }
    const fields = @typeInfo(Switches).Struct.fields;
    for (fields, 0..) |field, field_idx| {
        if (!@hasField(Flags, field.name)) compileError(
            "switch name does not match any fields: '{s}'",
            .{field.name},
        );

        if (field.type != comptime_int) compileError(
            "invalid switch type for '{s}': {s}",
            .{ field.name, @typeName(field.type) },
        );

        const switch_val = @field(Flags.switches, field.name);
        if (@TypeOf(switch_val) != comptime_int) {
            compileError("switch value is not a character: {any}", .{switch_val});
        }
        const switch_char = std.math.cast(u8, switch_val) orelse {
            compileError("switch value is not a character: {any}", .{switch_val});
        };
        if (!std.ascii.isAlphanumeric(switch_char)) {
            compileError("switch character is not a letter: {c}", .{switch_char});
        }
        if (switch_char == 'h') {
            compileError("switch value 'h' is reserved for the help message: {s}", .{field.name});
        }

        for (fields[field_idx + 1 ..]) |other_field| {
            const other = @field(Flags.switches, other_field.name);
            if (switch_val == other) compileError(
                "duplicated switch values: '{s}' and '{s}'",
                .{ field.name, other.name },
            );
        }
    }
}

pub fn validateDescriptions(comptime Command: type, comptime Descriptions: type) void {
    std.debug.assert(@inComptime());
    if (@typeInfo(Descriptions) != .Struct) {
        compileError("'descriptions' is not a struct", .{});
    }
    for (std.meta.fields(Descriptions)) |desc| {
        if (!@hasField(Command, desc.name)) {
            compileError("description does not match any field: '{s}'", .{desc.name});
        }
        if (!meta.isString(desc.type)) {
            compileError("description is not a string for '{s}'", .{desc.name});
        }
    }
}
