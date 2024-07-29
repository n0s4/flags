const std = @import("std");

/// Converts `my_zig_field` to `--my-zig-field` at comptime for comparison to command line flags.
pub fn flagName(comptime field: std.builtin.Type.StructField) []const u8 {
    // TODO: why do we need `comptime` here?
    return "--" ++ comptime toKebab(field.name);
}

pub fn positionalName(comptime field: std.builtin.Type.StructField) []const u8 {
    comptime var upper: []const u8 = &.{};
    comptime for (field.name) |c| {
        upper = upper ++ &[_]u8{std.ascii.toUpper(c)};
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
