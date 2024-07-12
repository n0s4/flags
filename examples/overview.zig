const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const result = flags.parse(&args, Flags, .{});

    try std.json.stringify(
        result,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}

const Flags = struct {
    // This field is required for your top-level command, and is used in help messages.
    pub const name = "example";

    // You can provide a description of your command which will be displayed between
    // the auto-generated usage and command/option descriptions.
    pub const help =
        \\This is a dummy command for testing purposes.
        \\There are a bunch of options for demonstration purposes.
    ;

    // bool fields will be true if their flag (e.g "--force") is passed.
    // Note that you don't need to provide a default value for bools or optionals.
    force: bool,

    // All other field types will either be optional, provide a default value, or be required.
    optional: ?[]const u8, // this is set to null if this is not passed
    override: []const u8 = "defaulty",
    required: []const u8, // an error is caused if this is not passed

    // All int types are parsed automatically, with specific runtime errors if the value passed is invalid:
    age: ?u8,
    power: i32 = 9000,

    // restrict choice with enums:
    size: enum {
        small,
        medium,
        large,

        // These will be displayed in the '--help' message.
        pub const descriptions = .{
            .small = "The least big",
            .medium = "Not quite small, not quite big",
            .large = "The biggest",
        };
    } = .medium,

    // This optional declaration defines shorthands which can be chained e.g '-fs large'.
    pub const switches = .{
        .force = 'f',
        .age = 'a',
        .power = 'p',
        .size = 's',
    };

    // These are used in the '--help' message
    pub const descriptions = .{
        .force = "Use the force",
        .optional = "You don't need this one",
        .override = "You can change this if you want",
        .required = "You have to set this!",
        .age = "How old?",
        .power = "How strong?",
        .size = "How big?",
    };
};
