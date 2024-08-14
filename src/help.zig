const std = @import("std");
const meta = @import("meta.zig");

/// A help section with a heading and a list of items.
const Section = struct {
    title: []const u8,
    items: []const Item = &.{},
    max_name_len: usize = 0,

    /// A help item for a flag, command etc.
    const Item = struct {
        /// Name of the flag, enum variant, command, or positional argument.
        name: []const u8,
        description: ?[]const u8,
    };

    const indent = "  ";

    pub fn render(comptime section: Section) []const u8 {
        comptime var str: []const u8 = "\n" ++ section.title ++ ":\n\n";
        for (section.items) |item| {
            str = str ++ indent ++ item.name;
            if (item.description) |description| {
                str = str ++ indent ++ " " ** (section.max_name_len - item.name.len) ++ description;
            }
            str = str ++ "\n";
        }
        return str;
    }

    pub fn add(section: *Section, item: Item) void {
        section.max_name_len = @max(section.max_name_len, item.name.len);
        section.items = section.items ++ .{item};
    }
};

pub fn generate(
    comptime Flags: type,
    comptime info: meta.FlagsInfo,
    comptime command_seq: []const u8,
) []const u8 {
    // TODO: generate usage
    comptime var help: []const u8 = generateUsage(Flags, info, command_seq);

    if (@hasDecl(Flags, "description")) {
        const description: []const u8 = Flags.description; // must be a string
        help = help ++ "\n" ++ description ++ "\n";
    }

    const flag_descriptions = getDescriptions(Flags);
    var options = Section{ .title = "Options" };
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
        var arguments = Section{ .title = "Arguments" };
        for (info.positionals) |pos| arguments.add(.{
            .name = pos.arg_name,
            .description = @field(pos_descriptions, pos.field_name),
        });
        help = help ++ arguments.render();
    }

    if (info.subcommands.len > 0) {
        const sub_descriptions = getDescriptions(std.meta.FieldType(Flags, .command));
        var commands = Section{ .title = "Commands" };
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

    fn add(self: *Usage, item: []const u8) void {
        self.items = self.items ++ .{item};
    }

    pub fn render(self: Usage, comptime command_seq: []const u8) []const u8 {
        var usage: []const u8 = "Usage: " ++ command_seq;

        const indent_len = usage.len;
        const max_line_len = 80;
        var len_prev_lines = 0;

        for (self.items) |item| {
            if (usage.len + " ".len + item.len - len_prev_lines > max_line_len) {
                len_prev_lines = usage.len;
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
) []const u8 {
    var usage = Usage{};

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
            .force = "Do it more forcefully",
            .target = "Where to aim the laser",
            .choice = "Pick one",
        };
    };

    try std.testing.expectEqualStrings(
        \\Usage: test [options]
        \\
        \\This command is for testing purposes only!
        \\
        \\Options:
        \\
        \\  -f, --force   Do it more forcefully
        \\  -t, --target  Where to aim the laser
        \\  --choice      Pick one
        \\    one         First one
        \\    two         Second one
        \\    three       Third one
        \\  -h, --help    Show this help and exit
        \\
        \\Arguments:
        \\
        \\  <FILE>  The file name to use
        \\
        \\Commands:
        \\
        \\  init  Make a new thing
        \\  add   Add something to the thing
        \\
    , comptime generate(Flags, meta.info(Flags), "test"));

    const Init = std.meta.FieldType(std.meta.FieldType(Flags, .command), .init);
    try std.testing.expectEqualStrings(
        \\Usage: test init [options]
        \\
        \\Make something new!
        \\
        \\Options:
        \\
        \\  --quiet     shhhhh
        \\  -h, --help  Show this help and exit
        \\
    , comptime generate(Init, meta.info(Init), "test init"));
}
