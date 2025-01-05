const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    var parser = flags.Parser.init;
    const result = parser.parse(args, "errors", Flags, .{}) catch |err| {
        // This error is returned when "--help" is passed, not when an actual error occured.
        if (err == error.PrintedHelp) {
            std.posix.exit(0);
        }

        // The parser stores the name and generated help message for the command it was parsing,
        // these can be used for additional error reporting.

        std.debug.print(
            "Encountered error while parsing for command '{s}': {s}\n",
            .{ parser.command_name, @errorName(err) },
        );

        // Convenience for printing usage part of help message to stdout:
        try parser.printUsage();

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
