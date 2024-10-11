const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const stdout = std.io.getStdOut();

    // Diagnostics store the name and help info about the command being parsed.
    // You can use this to display help / usage if there is a parsing error.
    var diags: flags.Diagnostics = undefined;

    const result = flags.parse(&args, "errors", Flags, .{
        .diagnostics = &diags,
    }) catch |err| {
        // This error is returned when "--help" is passed, not when an actual error occured.
        if (err == error.PrintedHelp) {
            std.posix.exit(0);
        }

        std.debug.print(
            "\nEncountered error while parsing for command '{s}': {s}\n\n",
            .{ diags.command, @errorName(err) },
        );

        // Print command usage.
        // This assumes no command declares a custom "help" string, so it must be auto-generated.
        const help = diags.help.generated;
        try help.usage.render(stdout, flags.ColorScheme.default);

        std.posix.exit(1);
    };

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
