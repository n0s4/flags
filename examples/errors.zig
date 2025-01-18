const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    // A diagnostics struct can be passed, to which the name and help message of the most recently
    // parsed (sub)command will be stored. This can be used to provide extra information in the
    // case of an error.
    var diagnostics: flags.Diagnostics = undefined;
    const result = flags.parse(args, "errors", Flags, .{
        .diagnostics = &diagnostics,
    }) catch |err| {
        // This error is returned when "--help" is passed, not when an actual error occured.
        if (err == error.PrintedHelp) {
            std.posix.exit(0);
        }

        std.debug.print(
            "Encountered error while parsing for command '{s}': {s}\n",
            .{ diagnostics.command_name, @errorName(err) },
        );

        // Convenience for printing usage part of help message to stdout:
        try diagnostics.printUsage(&flags.ColorScheme.default);

        std.posix.exit(1);
    };

    const stdout = std.io.getStdOut();
    try std.json.stringify(
        result,
        .{ .whitespace = .indent_2 },
        stdout.writer(),
    );
}

const Flags = struct {
    pub const description =
        \\Showcase of error handling features.
    ;

    foo: bool,
    bar: []const u8,
};
