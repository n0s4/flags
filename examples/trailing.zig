const std = @import("std");
const flags = @import("flags");

const stdout = std.io.getStdOut().writer();

const Flags = struct {
    pub const name = "trailing-demo";

    flag: bool,
};

pub fn main() !void {
    // The primary `parse` function does not allow trailing arguments.
    // Trailing arguments can be collected via `parseWithBuffer` or `parseWithAllocator`.

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    // try withBuffer(&args);
    try withAllocator(&args, gpa.allocator());
}

fn withBuffer(args: *std.process.ArgIterator) !void {
    const max_args = 8;
    var trailing_args_buffer: [max_args][]const u8 = undefined;

    const result = flags.parseWithBuffer(&trailing_args_buffer, args, Flags, .{}) catch {
        flags.fatal("too many trailing arguments (max = {d})", .{max_args});
    };

    try std.json.stringify(
        result,
        .{ .whitespace = .indent_2 },
        stdout,
    );
}

fn withAllocator(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
    const result = flags.parseWithAllocator(allocator, args, Flags, .{}) catch {
        flags.fatal("out of memory", .{});
    };

    defer result.trailing.deinit(); // Trailing arguments are returned in an ArrayList.

    try std.json.stringify(
        result.command,
        .{ .whitespace = .indent_2 },
        stdout,
    );

    try stdout.print("\n\ntrailing:\n", .{});
    for (result.trailing.items) |trailing| {
        try stdout.print("{s}\n", .{trailing});
    }
}
