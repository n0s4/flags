const std = @import("std");
const flags = @import("flags");

const Flags = struct {
    pub const name = "positionals";

    flag: bool,
};

pub fn main() !void {
    // The primary `parse` function does not collect positional arguments.
    // Positional arguments can be collected either via a fixed-size buffer using `parseWithBuffer`.

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const max_args = 4; // pick a sensible limit, e.g 32
    var positional_args_buffer: [max_args][]const u8 = undefined;

    const result = flags.parseWithBuffer(&positional_args_buffer, &args, Flags, .{}) catch {
        flags.fatal("too many positional arguments (max = {d})", .{max_args});
    };

    try std.json.stringify(
        result,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}
