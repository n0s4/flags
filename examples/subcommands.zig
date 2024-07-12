const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const command = flags.parse(&args, Command, .{});

    try std.json.stringify(
        command,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}

const Command = union(enum) {
    pub const name = "subcommands";

    pub const help =
        \\Enables manipulation of 'items'.
        \\You can create, delete, move and edit items.
    ;

    pub const descriptions = .{
        .add = "Create a new item",
        .remove = "Delete an item",
        .change = "Edit or move an existing item",
    };

    add: struct {
        name: []const u8,
        pub const switches = .{
            .name = 'n',
        };
    },

    remove: struct {
        name: ?[]const u8,
        all: bool,

        pub const switches = .{
            .name = 'n',
            .all = 'a',
        };

        pub const descriptions = .{
            .all = "Remove all items",
        };
    },

    change: union(enum) {
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
