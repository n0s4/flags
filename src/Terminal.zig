const Terminal = @This();

const std = @import("std");
const ColorScheme = @import("ColorScheme.zig");

const tty = std.io.tty;
const AnyWriter = std.io.AnyWriter;
const File = std.fs.File;

writer: union(enum) {
    /// Used when the user passes a custom stdout/stderr writer.
    any: AnyWriter,
    /// Stored this way in order to keep ownership of the file handle.
    /// Used by default for stdout/stderr.
    file: File.Writer,
},
config: tty.Config,

pub fn fromFile(file: File) Terminal {
    return .{
        .writer = .{ .file = file.writer() },
        .config = tty.detectConfig(file),
    };
}

pub fn fromWriter(writer: AnyWriter) Terminal {
    return .{
        .writer = .{ .any = writer },
        .config = .no_color,
    };
}

pub fn print(
    terminal: Terminal,
    style: ColorScheme.Style,
    comptime format: []const u8,
    args: anytype,
) !void {
    for (style) |color| {
        try terminal.setColor(color);
    }

    try terminal.getWriter().print(format, args);

    if (style.len > 0) {
        try terminal.setColor(.reset);
    }
}

pub fn setColor(terminal: Terminal, color: tty.Color) !void {
    try terminal.config.setColor(terminal.getWriter(), color);
}

fn getWriter(terminal: *const Terminal) AnyWriter {
    return switch (terminal.writer) {
        .any => |aw| aw,
        .file => |*fw| fw.any(),
    };
}
