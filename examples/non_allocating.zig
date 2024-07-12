const std = @import("std");
const flags = @import("flags");

// If you want to collect positional arguments while still avoiding heap-allocation, create
// a fixed buffer to store them in and use `parseWithBuffer`.
pub fn main() !void {
    const max_args = 4;
    var positional_args_buffer: [max_args][]const u8 = undefined;

    var args = std.process.args();
    const result = flags.parseWithBuffer(&positional_args_buffer, &args, Command, .{}) catch {
        flags.fatal("too many arguments (max = {d})", .{max_args});
    };

    try std.json.stringify(
        result,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}
