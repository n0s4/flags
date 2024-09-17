const help = @import("help.zig");
const parse_mod = @import("parse.zig");

pub const parse = parse_mod.parse;
pub const parseOrExit = parse_mod.parseOrExit;

test {
    _ = help;
    _ = parse_mod;
}
