const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const result = flags.parse(&args, Overview, .{});

    try std.json.stringify(
        result,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}

// The name of your type should match your executable name, e.g "my-program" -> "MyProgram".
// This can be overridden in the call to `flags.parse`.
const Overview = struct {
    // Optional description of the program.
    pub const help =
        \\This is a dummy command for testing purposes.
        \\There are a bunch of options for demonstration purposes.
    ;

    // Optional description of some or all of the flags (must match field names in the struct).
    pub const descriptions = .{
        .force = "Use the force",
        .optional = "You don't need this one",
        .override = "You can change this if you want",
        .required = "You have to set this!",
        .age = "How old?",
        .power = "How strong?",
        .size = "How big?",
    };

    force: bool, // Set to `true` only if '--force' is passed.

    optional: ?[]const u8, // Set to null if not passed.
    override: []const u8 = "defaulty", // "defaulty" if not passed.
    required: []const u8, // fatal error if not passed.

    // Integer and float types are parsed automatically with specific error messages for bad input.
    age: ?u8,
    power: f32 = 9000,

    // Restrict choice with enums:
    size: enum {
        small,
        medium,
        large,

        // Displayed in the '--help' message.
        pub const descriptions = .{
            .small = "The least big",
            .medium = "Not quite small, not quite big",
            .large = "The biggest",
        };
    } = .medium,

    // The 'positional' field is a special field that defines arguments that are not associated
    // with any --flag. Hence the name "positional" arguments.
    positional: struct {
        first: []const u8,
        second: u32,
        // Optional positional arguments must come at the end.
        third: ?u8,
    },

    // Optional declaration to define shorthands. These can be chained e.g '-fs large'.
    pub const switches = .{
        .force = 'f',
        .age = 'a',
        .power = 'p',
        .size = 's',
    };
};
