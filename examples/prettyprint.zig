const std = @import("std");
const arguments = @import("arguments");

fn print(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(fmt, args) catch {};
}

/// Utility for pretty printing a parse result.
pub fn prettyPrint(config: anytype, args: []const []const u8) void {
    switch (@typeInfo(@TypeOf(config))) {
        .Struct => printOptions(config),
        .Union => printCommand(config),
        else => comptime unreachable,
    }

    print("\nPositional arguments:\n", .{});
    for (args) |arg| print("{s}\n", .{arg});
}

fn printCommand(command: anytype) void {
    const Commands = @TypeOf(command);
    const tag_name = @tagName(std.meta.activeTag(command));

    inline for (std.meta.fields(Commands)) |field| {
        if (std.mem.eql(u8, field.name, tag_name)) {
            print("{s} ", .{tag_name});
            switch (@typeInfo(field.type)) {
                .Struct => {
                    print("\n", .{});
                    printOptions(@field(command, field.name));
                },
                .Union => printCommand(@field(command, field.name)),
                else => unreachable,
            }
        }
    }
}

fn printOptions(options: anytype) void {
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        print("{s}: ", .{field.name});
        const value = @field(options, field.name);
        switch (field.type) {
            []const u8 => print("{s}", .{value}),
            ?[]const u8 => print("{?s}", .{value}),
            else => switch (@typeInfo(field.type)) {
                .Enum => print("{s}", .{@tagName(value)}),
                else => print("{any}", .{value}),
            },
        }
        print("\n", .{});
    }
}
