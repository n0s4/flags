const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const command = flags.parse(&args, GitCli, .{});

    try std.json.stringify(
        command,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}

/// A very stripped-down model of the git CLI.
const GitCli = union(enum) {
    pub const name = "git";

    init: Init,
    add: Add,
    commit: Commit,

    pub const descriptions = .{
        .init = "Create an empty Git repository or reinitialize an existing one",
        .add = "Add file contents to the index",
        .commit = "Record changes to the repository",
    };

    const Init = struct {
        template: ?[]const u8,
        bare: bool,
        quiet: bool,

        pub const switches = .{
            .quiet = 'q',
        };

        pub const descriptions = .{
            .template = "directory from which templates will be used",
            .bare = "create a bare repository",
            .quiet = "be quiet",
        };
    };

    const Add = struct {
        verbose: bool,
        all: bool,
        force: bool,

        pub const switches = .{
            .verbose = 'v',
            .all = 'A',
            .force = 'f',
        };

        pub const descriptions = .{
            .verbose = "be verbose",
            .all = "add changes from all tracked and untracked files",
            .force = "allow adding otherwise ignored files",
        };
    };

    const Commit = struct {
        quiet: bool,
        verbose: bool,
        all: bool,
        file: ?[]const u8,
        message: ?[]const u8,

        pub const switches = .{
            .quiet = 'q',
            .verbose = 'v',
            .all = 'a',
            .file = 'F',
            .message = 'm',
        };

        pub const descriptions = .{
            .quiet = "suppress summary after successful commit",
            .verbose = "show diff in commit message template",
            .all = "commit all changed files",
            .file = "read message from file",
            .message = "commit message",
        };
    };
};
