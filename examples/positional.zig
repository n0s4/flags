const std = @import("std");
const flags = @import("flags");

const Command = struct {
    pub const name = "positional";
    flag: bool,

    // The 'positional' field is a special field that defines arguments that are not associated
    // with any --flag. Hence the name "positional" arguments.
    positional: struct {
        first: []const u8,
        second: u32,
        // Optional positional arguments must come at the end.
        third: ?u8,
    },
};

pub fn main() !void {
    var args = std.process.args();

    const cmd = flags.parse(&args, Command, .{});

    try std.json.stringify(
        cmd,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}
