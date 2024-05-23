const std = @import("std");
const parser = @import("parser.zig");
const help = @import("help.zig");

pub const parse = parser.parse;
pub const fatal = parser.fatal;
pub const helpMessage = help.helpMessage;

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
