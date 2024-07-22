//! Utilities for type validation.

const std = @import("std");

pub fn compileError(comptime fmt: []const u8, args: anytype) void {
    @compileError("flags: " ++ std.fmt.comptimePrint(fmt, args));
}

/// Checks whether T is the type of a string literal or a []const u8.
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
