const std = @import("std");
const arguments = @import("arguments");

fn print(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(fmt, args) catch {};
}

/// Utility for pretty printing a parse result.
pub fn prettyPrint(config: anytype, args: []const []const u8) void {
    const Config = @TypeOf(config);

    inline for (std.meta.fields(Config)) |field| {
        print("{s}: ", .{field.name});
        const value = @field(config, field.name);
        switch (field.type) {
            []const u8 => print("{s}", .{value}),
            ?[]const u8 => print("{?s}", .{value}),
            else => print("{any}", .{value}),
        }
        print("\n", .{});
    }

    print("\nPositional arguments:\n", .{});
    for (args) |arg| print("{s}\n", .{arg});
}
