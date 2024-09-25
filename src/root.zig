const mod = @import("parse.zig");

const Help = @import("Help.zig");
pub const ColorScheme = @import("ColorScheme.zig");
pub const Terminal = @import("Terminal.zig");

pub const Error = mod.Error;
pub const Diagnostics = mod.Diagnostics;
pub const Options = mod.Options;

pub const parse = mod.parse;
pub const parseOrExit = mod.parseOrExit;

test {
    _ = Help;
}
