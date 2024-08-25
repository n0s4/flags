const std = @import("std");
const meta = @import("meta.zig");
const cons = @import("console.zig");

const fmt_green_bold: []const u8 = cons.fg_green ++ cons.text_bold;
const fmt_white_bold: []const u8 = cons.fg_white ++ cons.text_bold;
const fmt_magenta_bold: []const u8 = cons.fg_magenta ++ cons.text_bold;

/// A help section with a heading and a list of items.
const Section = struct {
    title: []const u8,
    items: []const Item = &.{},
    max_name_len: usize = 0,
    max_line_len: usize = 80,

    /// A help item for a flag, command etc.
    const Item = struct {
        /// Name of the flag, enum variant, command, or positional argument.
        name: []const u8,
        description: ?[]const u8,
    };

    const indent = "  ";

    /// Render the help section to a comptime string
    pub fn render(comptime section: Section) []const u8 {
        comptime var str: []const u8 = "\n" ++ fmt_green_bold ++ section.title ++ ":" ++ cons.ansi_end ++ "\n\n";
        for (section.items) |item| {
            str = str ++ indent ++ fmt_white_bold ++ item.name ++ cons.ansi_end;
            if (item.description) |description| {
                str = str ++ indent ++ " " ** (section.max_name_len - item.name.len);

                // Automatically line-wrap the description, with a base indent at the current column
                const base_indent: usize = indent.len + section.max_name_len;
                comptime var col: usize = base_indent;
                comptime var words = std.mem.tokenize(u8, description, " \r\n");
                inline while (words.next()) |word| {
                    if (col + word.len > section.max_line_len) {
                        str = str ++ "\n" ++ indent ** 2 ++ " " ** (section.max_name_len);
                        col = base_indent - 1;
                    }
                    if (col > base_indent) {
                        str = str ++ " " ++ word;
                    } else {
                        str = str ++ word;
                    }
                    col += word.len + 1;
                }
            }
            str = str ++ "\n";
        }
        return str;
    }

    pub fn add(comptime section: *Section, comptime item: Item) void {
        section.max_name_len = @max(section.max_name_len, item.name.len);
        section.items = section.items ++ .{item};
    }
};

/// Print the help (usage) message for the application
pub fn printUsage(comptime Flags: type, comptime command_name: ?[]const u8, comptime max_line_len: usize, writer: anytype) !void {
    const name: []const u8 = comptime command_name orelse meta.commandName(Flags);
    const help: []const u8 = comptime generate(Flags, meta.info(Flags), name, max_line_len);
    try writer.writeAll(help);
}

/// Generage help (usage) message string for the application
pub fn generate(
    comptime Flags: type,
    comptime info: meta.FlagsInfo,
    comptime command_seq: []const u8,
    comptime max_line_len: usize,
) []const u8 {
    comptime var help: []const u8 = generateUsage(Flags, info, command_seq, max_line_len);

    if (@hasDecl(Flags, "description")) {
        const description: []const u8 = Flags.description; // must be a string
        help = help ++ "\n" ++ fmt_magenta_bold ++ description ++ cons.ansi_end ++ "\n";
    }

    const flag_descriptions = getDescriptions(Flags);
    var options = Section{ .title = "Options", .max_line_len = max_line_len };
    for (info.flags) |flag| {
        options.add(.{
            .name = if (flag.switch_char) |ch|
                std.fmt.comptimePrint("-{c}, {s}", .{ ch, flag.flag_name })
            else
                flag.flag_name,

            .description = @field(flag_descriptions, flag.field_name),
        });
        if (@typeInfo(meta.unwrapOptional(flag.type)) == .Enum) {
            const variant_descriptions = getDescriptions(flag.type);
            for (@typeInfo(flag.type).Enum.fields) |variant| {
                options.add(.{
                    .name = Section.indent ++ meta.toKebab(variant.name),
                    .description = @field(variant_descriptions, variant.name),
                });
            }
        }
    }

    options.add(.{
        .name = "-h, --help",
        .description = "Show this help and exit",
    });

    help = help ++ options.render();

    if (info.positionals.len > 0) {
        const pos_descriptions = getDescriptions(std.meta.FieldType(Flags, .positional));
        var arguments = Section{ .title = "Arguments", .max_line_len = max_line_len };
        for (info.positionals) |pos| arguments.add(.{
            .name = pos.arg_name,
            .description = @field(pos_descriptions, pos.field_name),
        });
        help = help ++ arguments.render();
    }

    if (info.subcommands.len > 0) {
        const sub_descriptions = getDescriptions(std.meta.FieldType(Flags, .command));
        var commands = Section{ .title = "Commands", .max_line_len = max_line_len };
        for (info.subcommands) |cmd| commands.add(.{
            .name = cmd.command_name,
            .description = @field(sub_descriptions, cmd.field_name),
        });
        help = help ++ commands.render();
    }

    return help;
}

fn Descriptions(comptime T: type) type {
    return std.enums.EnumFieldStruct(
        std.meta.FieldEnum(T),
        ?[]const u8,
        @as(?[]const u8, null),
    );
}

fn getDescriptions(comptime S: type) Descriptions(S) {
    var descriptions: Descriptions(S) = .{};

    if (@hasDecl(S, "descriptions")) {
        const D = @TypeOf(S.descriptions);
        if (@typeInfo(D) != .Struct) meta.compileError(
            "descriptions is not a struct value: {s}",
            .{@typeName(D)},
        );

        for (@typeInfo(D).Struct.fields) |desc| {
            if (!@hasField(S, desc.name)) meta.compileError(
                "description name does not match any field: {s}",
                .{desc.name},
            );

            const desc_val = @field(S.descriptions, desc.name);
            @field(descriptions, desc.name) =
                @as([]const u8, desc_val); // description must be a string
        }
    }

    return descriptions;
}

const Usage = struct {
    items: []const []const u8 = &.{},
    max_line_len: usize = 80,

    fn add(self: *Usage, item: []const u8) void {
        self.items = self.items ++ .{item};
    }

    pub fn render(self: Usage, comptime command_seq: []const u8) []const u8 {
        var usage: []const u8 = fmt_green_bold ++ "Usage: " ++ cons.ansi_end ++ command_seq;
        const ansi_codes_len = fmt_green_bold.len + cons.ansi_end.len;

        const indent_len = usage.len - ansi_codes_len;
        var len_prev_lines = 0;

        for (self.items) |item| {
            const cur_len = usage.len - ansi_codes_len;
            if (cur_len + " ".len + item.len - len_prev_lines > self.max_line_len) {
                len_prev_lines = cur_len;
                usage = usage ++ "\n" ++ " " ** indent_len;
            }
            usage = usage ++ " " ++ item;
        }

        return usage;
    }
};

fn generateUsage(
    comptime Flags: type,
    comptime info: meta.FlagsInfo,
    comptime command_seq: []const u8,
    comptime max_line_len: usize,
) []const u8 {
    var usage = Usage{ .max_line_len = max_line_len };

    const flag_formats = getFormats(Flags);
    for (info.flags) |flag| {
        var flag_usage: []const u8 = "";

        if (flag.switch_char) |switch_char| {
            flag_usage = flag_usage ++ std.fmt.comptimePrint("-{c} | ", .{switch_char});
        }

        flag_usage = flag_usage ++ flag.flag_name;

        if (flag.type != bool) {
            const format = @field(flag_formats, flag.field_name) orelse
                "<" ++ flag.flag_name[2..] ++ ">"; // chop off the leading "--"

            flag_usage = flag_usage ++ " " ++ format;
        }

        if (flag.type == bool or @typeInfo(flag.type) == .Optional or flag.default_value != null) {
            flag_usage = "[" ++ flag_usage ++ "]";
        }

        usage.add(flag_usage);
    }

    for (info.positionals) |arg| {
        const arg_usage = if (@typeInfo(arg.type) == .Optional or arg.default_value != null)
            "[" ++ arg.arg_name ++ "]"
        else
            arg.arg_name;

        usage.add(arg_usage);
    }

    if (info.subcommands.len > 0) {
        usage.add("<command>");
    }

    return usage.render(command_seq) ++ "\n";
}

fn Formats(comptime T: type) type {
    return std.enums.EnumFieldStruct(
        std.meta.FieldEnum(T),
        ?[]const u8,
        @as(?[]const u8, null),
    );
}

fn getFormats(comptime S: type) Formats(S) {
    var formats: Formats(S) = .{};

    if (@hasDecl(S, "formats")) {
        const F = @TypeOf(S.formats);
        if (@typeInfo(F) != .Struct) meta.compileError(
            "formats is not a struct value: {s}",
            .{@typeName(F)},
        );

        for (@typeInfo(F).Struct.fields) |format| {
            if (!@hasField(S, format.name)) meta.compileError(
                "format name does not match any field: {s}",
                .{format.name},
            );

            const format_val = @field(S.formats, format.name);
            @field(formats, format.name) =
                @as([]const u8, format_val); // format must be a string
        }
    }

    return formats;
}

test generate {
    const Flags = struct {
        pub const description =
            \\This command is for testing purposes only!
        ;

        force: bool,
        target: ?[]const u8,
        choice: enum {
            one,
            two,
            three,

            pub const descriptions = .{
                .one = "First one",
                .two = "Second one",
                .three = "Third one",
            };
        },

        positional: struct {
            file: []const u8,

            pub const descriptions = .{
                .file = "The file name to use",
            };
        },

        command: union(enum) {
            pub const descriptions = .{
                .init = "Make a new thing",
                .add = "Add something to the thing",
            };
            init: struct {
                pub const description = "Make something new!";
                pub const descriptions = .{
                    .quiet = "shhhhh",
                };
                quiet: bool,
            },
            add: struct {
                force: bool,
            },
        },

        pub const switches = .{
            .force = 'f',
            .target = 't',
        };

        pub const descriptions = .{
            .force = "Do it more forcefully. This is a very long description so that a line wrap is inevitable.",
            .target = "Where to aim the laser",
            .choice = "Pick one",
        };
    };

    {
        const help_usage = fmt_green_bold ++ "Usage: " ++ cons.ansi_end;
        comptime var usage_str: []const u8 =
            \\test [-f | --force] [-t | --target <target>] --choice <choice> <FILE>
            \\            <command>
            \\
            \\
        ;
        usage_str = usage_str ++ fmt_magenta_bold ++ "This command is for testing purposes only!" ++ cons.ansi_end ++ "\n";

        const help_options = "\n" ++ fmt_green_bold ++ "Options:" ++ cons.ansi_end ++ "\n\n";
        comptime var opts_str: []const u8 = "  " ++ fmt_white_bold ++ "-f, --force" ++ cons.ansi_end ++ "   Do it more forcefully. ";
        opts_str = opts_str ++ "This is a very long description so that a line\n                wrap is inevitable.\n";
        opts_str = opts_str ++ "  " ++ fmt_white_bold ++ "-t, --target" ++ cons.ansi_end ++ "  Where to aim the laser\n";
        opts_str = opts_str ++ "  " ++ fmt_white_bold ++ "--choice" ++ cons.ansi_end ++ "      Pick one\n";
        opts_str = opts_str ++ "  " ++ fmt_white_bold ++ "  one" ++ cons.ansi_end ++ "         First one\n";
        opts_str = opts_str ++ "  " ++ fmt_white_bold ++ "  two" ++ cons.ansi_end ++ "         Second one\n";
        opts_str = opts_str ++ "  " ++ fmt_white_bold ++ "  three" ++ cons.ansi_end ++ "       Third one\n";
        opts_str = opts_str ++ "  " ++ fmt_white_bold ++ "-h, --help" ++ cons.ansi_end ++ "    Show this help and exit\n";

        const help_args = "\n" ++ fmt_green_bold ++ "Arguments:" ++ cons.ansi_end ++ "\n\n";
        const args_str = "  " ++ fmt_white_bold ++ "<FILE>" ++ cons.ansi_end ++ "  The file name to use\n";

        const help_commands = "\n" ++ fmt_green_bold ++ "Commands:" ++ cons.ansi_end ++ "\n\n";
        comptime var cmds_str: []const u8 = "  " ++ fmt_white_bold ++ "init" ++ cons.ansi_end ++ "  Make a new thing\n";
        cmds_str = cmds_str ++ "  " ++ fmt_white_bold ++ "add" ++ cons.ansi_end ++ "   Add something to the thing\n";

        const help_text = help_usage ++ usage_str ++ help_options ++ opts_str ++ help_args ++ args_str ++ help_commands ++ cmds_str;
        try std.testing.expectEqualStrings(help_text, comptime generate(Flags, meta.info(Flags), "test", 85));
    }

    {
        comptime var usage_str: []const u8 = fmt_green_bold ++ "Usage: " ++ cons.ansi_end ++ "test init [--quiet]\n";
        usage_str = usage_str ++ "\n" ++ fmt_magenta_bold ++ "Make something new!" ++ cons.ansi_end ++ "\n";
        usage_str = usage_str ++ "\n" ++ fmt_green_bold ++ "Options:" ++ cons.ansi_end ++ "\n\n";
        usage_str = usage_str ++ "  " ++ fmt_white_bold ++ "--quiet" ++ cons.ansi_end ++ "     shhhhh\n";
        usage_str = usage_str ++ "  " ++ fmt_white_bold ++ "-h, --help" ++ cons.ansi_end ++ "  Show this help and exit\n";

        const Init = std.meta.FieldType(std.meta.FieldType(Flags, .command), .init);
        try std.testing.expectEqualStrings(usage_str, comptime generate(Init, meta.info(Init), "test init", 85));
    }
}
