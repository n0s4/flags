const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    // Contains info about a (sub)command where a parsing error occured.
    var diagnositics: flags.Diagnostics = undefined;

    // Replace with your writer for reporting errors.
    // Using stderr explicitly is redundant as flags uses stderr by default.
    var error_writer = std.io.getStdErr().writer();

    const options = flags.parse(&args, "error-handling", Flags, .{
        .diagnostics = &diagnositics,
        .stderr = error_writer.any(),
    }) catch |err| {
        // When parsing is stopped due to --help being passed, this special error is returned.
        if (err == flags.Error.PrintedHelp) {
            // In this case help has already been printed to stdout and
            // no actual parsing error has occured so we exit.
            std.posix.exit(0);
        }

        std.debug.print(
            "caught {!} while parsing command \"{s}\"\n",
            .{ err, diagnositics.command },
        );

        std.debug.print("command help:\n{s}", .{diagnositics.help});

        std.posix.exit(1);
    };

    try std.json.stringify(
        options,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}

const Flags = struct {
    pub const description = "Test program to showcase error handling.";

    foo: bool,
    bar: ?[]const u8,

    command: union(enum) {
        baz: struct {
            a: bool,
        },
        qux: struct {
            b: bool,
        },
    },
};
