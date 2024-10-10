const Terminal = @This();

const std = @import("std");
const ColorScheme = @import("ColorScheme.zig");

const tty = std.io.tty;
const File = std.fs.File;

writer: File.Writer,
config: tty.Config,

pub fn init(file: File) Terminal {
    return .{
        .writer = file.writer(),
        .config = tty.detectConfig(file),
    };
}

pub fn print(
    terminal: Terminal,
    style: ColorScheme.Style,
    comptime format: []const u8,
    args: anytype,
) File.WriteError!void {
    for (style) |color| {
        try terminal.config.setColor(terminal.writer, color);
    }

    try terminal.writer.print(format, args);

    if (style.len > 0) {
        try terminal.config.setColor(terminal.writer, .reset);
    }
}
