const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const options = flags.parseOrExit(args, "overview", Flags, .{});

    try std.json.stringify(
        options,
        .{ .whitespace = .indent_2 },
        std.io.getStdOut().writer(),
    );
}

const Flags = struct {
    // Optional description of the program.
    pub const description =
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

        pub const descriptions = .{
            .first = "The first argument (required)",
            .second = "The second argument (required)",
            .third = "The third argument (optional)",
        };
    },

    // Subcommands can be defined through the `command` field, which should be a union with struct
    // fields which are defined the same way this struct is. Subcommands may be nested.
    command: union(enum) {
        frobnicate: struct {
            pub const descriptions = .{
                .level = "Frobnication level",
            };

            level: u8,
        },
        defrabulise: struct {
            supercharge: bool,
        },

        pub const descriptions = .{
            .frobnicate = "Frobnicate everywhere",
            .defrabulise = "Defrabulise everyone",
        };
    },

    // Optional declaration to define shorthands. These can be chained e.g '-fs large'.
    pub const switches = .{
        .force = 'f',
        .age = 'a',
        .power = 'p',
        .size = 's',
    };
};
