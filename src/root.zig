const std = @import("std");
const parser = @import("parser.zig");
const help = @import("help.zig");

pub usingnamespace parser;
// pub const helpMessage = help.helpMessage;

test {
    _ = help;
}
