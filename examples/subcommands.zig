const std = @import("std");
const arguments = @import("arguments");
const prettyPrint = @import("prettyprint.zig").prettyPrint;

const Command = union(enum) {
    add: struct {
        force: bool,
        verbose: bool,
        all: bool,
    },

    commit: struct {
        all: bool,
        message: []const u8,
    },

    nested: union(enum) {
        first: struct {
            target: []const u8,
        },

        second: struct {
            size: enum { small, medium, big } = .big,

            // Switches can be defined at any level.
            pub const switches = .{
                .size = 's',
            };
        },
    },
};

pub fn main() !void {
    var args = std.process.args();

    const result = arguments.parse(&args, Command);

    prettyPrint(result.config, result.args);
}
