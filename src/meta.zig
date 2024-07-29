const std = @import("std");

pub fn compileError(comptime fmt: []const u8, args: anytype) void {
    @compileError("(flags) " ++ std.fmt.comptimePrint(fmt, args));
}

/// Whether T is the type of a string literal or a []const u8.
pub fn isString(comptime T: type) bool {
    if (T == []const u8) return true;
    // String literals have the type *const [len:0]u8
    switch (@typeInfo(T)) {
        .Pointer => |p| {
            const child = @typeInfo(p.child);
            return p.is_const and
                child == .Array and
                child.Array.child == u8;
        },
        else => return false,
    }
}

pub fn unwrapOptional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Optional => |opt| opt.child,
        else => T,
    };
}

pub fn defaultValue(comptime field: std.builtin.Type.StructField) ?field.type {
    const default_opaque = field.default_value orelse return null;
    const default: *const field.type = @ptrCast(@alignCast(default_opaque));
    return default.*;
}

pub fn fields(comptime T: type) []const std.builtin.Type.StructField {
    return @typeInfo(T).Struct.fields;
}
