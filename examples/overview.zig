const std = @import("std");
const arguments = @import("arguments");
const prettyPrint = @import("prettyprint.zig").prettyPrint;

const Config = struct {
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
    use_color: enum { never, auto, always } = .auto,
    // note that enum variants are detected in kebab-case: "--job scrum-master"
    job: ?enum { ceo, scrum_master, developer },

    // Optionally, this declaration defines shorthands which can be chained e.g '-fc always'.
    // Note that this must be marked `pub`.
    pub const switches = .{
        .force = 'f',
        .use_color = 'c',
    };
};

// Optionally, you can specify the size of the buffer for positional arguments if you wish to
// impose a specific limit or you expect more arguments than the default (32).
pub const max_positional_arguments = 3;

pub fn main() !void {
    var args = std.process.args();

    const result = arguments.parse(&args, Config);

    prettyPrint(
        result.config, // result, of passed `Config` type
        result.args, // extra positional arguments
    );
}
