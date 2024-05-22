const std = @import("std");

/// Converts `my_zig_field` to `--my-zig-field` at comptime for comparison to command line flags.
pub fn flagName(comptime field: std.builtin.Type.StructField) []const u8 {
    return "--" ++ comptime toKebab(field.name);
}

/// Converts from snake_case to kebab-case at comptime.
pub fn toKebab(comptime string: []const u8) []const u8 {
    return comptime blk: {
        var name: []const u8 = "";

        for (string) |ch| name = name ++ .{switch (ch) {
            '_' => '-',
            else => ch,
        }};

        break :blk name;
    };
}
