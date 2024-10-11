const Help = @This();

const std = @import("std");
const meta = @import("meta.zig");

const File = std.fs.File;
const ColorScheme = @import("ColorScheme.zig");
const Terminal = @import("Terminal.zig");

usage: Usage,
description: ?[]const u8,
sections: []const Section,

pub const Usage = struct {
    const max_line_len = 80;

    command: []const u8,
    body: []const u8,

    pub fn render(usage: Usage, stdout: File, colors: ColorScheme) File.WriteError!void {
        const term = Terminal.init(stdout);
        try usage.renderToTerminal(term, colors);
    }

    pub fn renderToTerminal(usage: Usage, term: Terminal, colors: ColorScheme) !void {
        try term.print(colors.header, "Usage: ", .{});
        try term.print(colors.command_name, "{s}", .{usage.command});
        try term.print(colors.usage, "{s}\n", .{usage.body});
    }

    pub fn generate(Flags: type, info: meta.FlagsInfo, command: []const u8) Usage {
        var usage = Usage{ .command = command, .body = &.{} };
        var line_len = "Usage: ".len + command.len;

        const flag_formats = meta.getFormats(Flags);
        for (info.flags) |flag| {
            var flag_usage: []const u8 = "";

            if (flag.switch_char) |ch| {
                flag_usage = flag_usage ++ std.fmt.comptimePrint("-{c} | ", .{ch});
            }

            flag_usage = flag_usage ++ flag.flag_name;

            if (flag.type != bool) {
                const format = @field(flag_formats, flag.field_name) orelse flag.flag_name[2..];
                flag_usage = flag_usage ++ " <" ++ format ++ ">";
            }

            if (flag.isOptional()) {
                flag_usage = "[" ++ flag_usage ++ "]";
            }

            usage.add(flag_usage, &line_len);
        }
        usage.add("[-h | --help]", &line_len);

        for (info.positionals) |arg| {
            const arg_usage = if (arg.isOptional())
                std.fmt.comptimePrint("[{s}]", .{arg.arg_name})
            else
                arg.arg_name;

            usage.add(arg_usage, &line_len);
        }

        if (info.subcommands.len > 0) {
            usage.add("<command>", &line_len);
        }

        return usage;
    }

    fn add(usage: *Usage, item: []const u8, line_len: *usize) void {
        if (line_len.* + " ".len + item.len > max_line_len) {
            const indent_len = "Usage: ".len + usage.command.len;
            usage.body = usage.body ++ "\n" ++ " " ** indent_len;
            line_len.* = indent_len;
        }

        usage.body = usage.body ++ " " ++ item;
        line_len.* += 1 + item.len;
    }
};

const Section = struct {
    header: []const u8,
    items: []const Item = &.{},
    max_name_len: usize = 0,

    const Item = struct {
        name: []const u8,
        desc: ?[]const u8,
    };

    pub fn add(section: *Section, item: Item) void {
        section.items = section.items ++ .{item};
        section.max_name_len = @max(section.max_name_len, item.name.len);
    }
};

pub fn render(help: Help, stdout: File, colors: ColorScheme) File.WriteError!void {
    const term = Terminal.init(stdout);
    try help.usage.renderToTerminal(term, colors);

    if (help.description) |description| {
        try term.print(colors.command_description, "\n{s}\n", .{description});
    }

    for (help.sections) |section| {
        try term.print(colors.header, "\n{s}\n\n", .{section.header});

        for (section.items) |item| {
            try term.print(colors.option_name, "  {s}", .{item.name});
            if (item.desc) |desc| {
                try term.print(&.{}, " ", .{});
                for (0..(section.max_name_len - item.name.len)) |_| {
                    try term.print(&.{}, " ", .{});
                }
                try term.print(colors.description, "{s}", .{desc});
            }

            try term.print(&.{}, "\n", .{});
        }
    }
}

pub fn generate(Flags: type, info: meta.FlagsInfo, command: []const u8) Help {
    var help = Help{
        .usage = Usage.generate(Flags, info, command),
        .description = if (@hasDecl(Flags, "description"))
            @as([]const u8, Flags.description) // description must be a string
        else
            null,
        .sections = &.{},
    };

    const flag_descriptions = meta.getDescriptions(Flags);
    var options = Section{ .header = "Options:" };
    for (info.flags) |flag| {
        options.add(.{
            .name = if (flag.switch_char) |ch|
                std.fmt.comptimePrint("-{c}, {s}", .{ ch, flag.flag_name })
            else
                flag.flag_name,

            .desc = @field(flag_descriptions, flag.field_name),
        });

        const T = meta.unwrapOptional(flag.type);
        if (@typeInfo(T) == .Enum) {
            const variant_descriptions = meta.getDescriptions(T);
            for (@typeInfo(T).Enum.fields) |variant| {
                options.add(.{
                    .name = "  " ++ variant.name,
                    .desc = @field(variant_descriptions, variant.name),
                });
            }
        }
    }

    options.add(.{
        .name = "-h, --help",
        .desc = "Show this help and exit",
    });

    help.sections = help.sections ++ .{options};

    if (info.positionals.len > 0) {
        const pos_descriptions = meta.getDescriptions(std.meta.FieldType(Flags, .positional));
        var arguments = Section{ .header = "Arguments:" };
        for (info.positionals) |arg| arguments.add(.{
            .name = arg.arg_name,
            .desc = @field(pos_descriptions, arg.field_name),
        });
        help.sections = help.sections ++ .{arguments};
    }
    if (info.subcommands.len > 0) {
        const cmd_descriptions = meta.getDescriptions(std.meta.FieldType(Flags, .command));
        var commands = Section{ .header = "Commands:" };
        for (info.subcommands) |cmd| commands.add(.{
            .name = cmd.command_name,
            .desc = @field(cmd_descriptions, cmd.field_name),
        });
        help.sections = help.sections ++ .{commands};
    }

    return help;
}

const testing = std.testing;

test Help {
    const Flags = struct {
        pub const description =
            \\This command is for testing the help generation and rendering.
        ;

        pub const descriptions = .{
            .flag = "Enable the flag",
            .string = "Specify a string",
            .choice = "Choose one",
        };

        pub const formats = .{
            .string = "text",
        };

        pub const switches = .{
            .flag = 'f',
        };

        flag: bool,
        string: []const u8,
        choice: ?enum {
            alpha,
            beta,

            pub const descriptions = .{
                .alpha = "The first letter",
                .beta = "The latter letter",
            };
        },

        positional: struct {
            pub const descriptions = .{
                .file = "Path to the file",
                .password = "Secret password",
            };

            file: []const u8,
            password: ?u8,
        },

        command: union(enum) {
            pub const descriptions = .{
                .run = "Move fast",
                .jump = "Jump high",
            };

            run: struct {
                speed: f32 = 5,
            },

            jump: struct {
                height: f32 = 3,
            },
        },
    };

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    const terminal = Terminal.fromWriter(output.writer().any());

    const help = comptime generate(Flags, meta.info(Flags), "test");
    try help.renderToTerminal(terminal, ColorScheme.default);

    try testing.expectEqualStrings(
        \\Usage: test [-f | --flag] --string <text> [--choice <choice>] [-h | --help]
        \\            <FILE> [<PASSWORD>] <command>
        \\
        \\This command is for testing the help generation and rendering.
        \\
        \\Options:
        \\
        \\-f, --flag Enable the flag
        \\--string   Specify a string
        \\--choice   Choose one
        \\  alpha    The first letter
        \\  beta     The latter letter
        \\-h, --help Show this help and exit
        \\
        \\Arguments:
        \\
        \\<FILE>     Path to the file
        \\<PASSWORD> Secret password
        \\
        \\Commands:
        \\
        \\run  Move fast
        \\jump Jump high
        \\
    , output.items);
}
