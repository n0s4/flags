const std = @import("std");
const flags = @import("flags");
const prettyPrint = @import("prettyprint.zig").prettyPrint;

const Command = union(enum) {
    pub const name = "subcommands";

    add: struct {
        name: []const u8,
        pub const switches = .{
            .name = "n",
        };
    },

    remove: struct {
        name: ?[]const u8,
        all: bool,

        pub const switches = .{
            .name = "n",
            .all = "a",
        };

        pub const descriptions = .{
            .all = "Remove all items",
        };
    },

    nested: union(enum) {
        edit: struct {
            title: ?[]const u8,
            content: ?[]const u8,

            pub const descriptions = .{
                .title = "New title",
                .content = "New content",
            };
        },

        move: struct {
            from: []const u8,
            to: []const u8,

            pub const switches = .{
                .from = 'f',
                .to = 't',
            };
        },
    },
};

pub fn main() !void {
    var args = std.process.args();

    const result = flags.parse(&args, Command);

    prettyPrint(result.config, result.args);
}
