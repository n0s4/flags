const std = @import("std");
const flags = @import("flags");

const Command = struct {
    pub const name = "positionals";
    flag: bool,
    positional: struct {
        p1: []const u8,
        p2: u32,
        p3: ?u8,
    },
};

pub fn main() !void {
    var args = std.process.args();
    var buf: [2][]const u8 = undefined;

    const cmd = flags.parseWithBuffer(&buf, &args, Command, .{}) catch unreachable;

    try std.json.stringify(
        cmd,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}
