const std = @import("std");
const arguments = @import("parse.zig");

const print = std.debug.print;

const Config = struct {
    // bools and optionals will be set to false/null if their flags are not passed:
    force: bool,
    target: ?[]const u8,

    // non-optional types can have a default, or be required:
    override: []const u8 = "defaulty",
    required: []const u8,

    // ints are parsed automatically:
    age: ?u8,
    power: i32 = 9000,

    // restrict choice with enums:
    use_color: enum { never, auto, always } = .auto,
    job: ?enum { ceo, software_developer, product_manager },

    /// This field is required for storing positional arguments.
    /// A global-scoped fixed buffer is used during parsing to store these to avoid allocation,
    /// this is a slice into that buffer.
    args: []const []const u8,

    /// Optional declaration defines shorthands which can be chained e.g '-ft foo'.
    /// Note that this must be marked `pub`.
    pub const switches = .{
        .force = 'f',
        .target = 't',
        .override = 'o',
        .required = 'r',
        .age = 'a',
        .power = 'p',
        .use_color = 'c',
        .job = 'j',
    };
};

pub fn main() !void {
    var args = std.process.args();

    const result = arguments.parse(&args, Config);

    printConfig(result);
}
fn printConfig(config: Config) void {
    inline for (std.meta.fields(Config)) |field| {
        if (comptime std.mem.eql(u8, field.name, "args")) continue;

        print("{s}: ", .{field.name});
        const value = @field(config, field.name);
        switch (field.type) {
            []const u8 => print("{s}", .{value}),
            ?[]const u8 => print("{?s}", .{value}),
            else => print("{any}", .{value}),
        }
        print("\n", .{});
    }

    print("\nPositional arguments:\n", .{});
    for (config.args) |arg| print("{s}\n", .{arg});
}
