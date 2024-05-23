const std = @import("std");
const flags = @import("flags");
const prettyPrint = @import("prettyprint.zig").prettyPrint;

// Optionally, you can specify the size of the buffer for positional arguments if you wish to
// impose a specific limit or you expect more than the default (32).
pub const max_positional_flags = 3;

pub fn main() !void {
    var args = std.process.args();
    const result = flags.parse(&args, Command);

    prettyPrint(
        result.flags, // result, has type of `Command`
        result.args, // extra positional arguments
    );
}

const Command = struct {
    // This field is required for your top-level command, and is used in help messages.
    pub const name = "example";

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
