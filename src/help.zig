const std = @import("std");
const format = @import("format.zig");

pub fn helpMessage(comptime Command: type, comptime name: []const u8) []const u8 {
    if (@hasDecl(Command, "full_help")) {
        return Command.full_help;
    }

    if (std.meta.fields(Command).len == 0) return "Usage: " ++ name ++ "\n";
    return switch (@typeInfo(Command)) {
        .Struct => helpFlags(Command, name),
        .Union => helpCommands(Command, name),
        else => comptime unreachable,
    };
}

const indent = "  ";

/// This is used during comptime to collect info about flags/commands.
/// The `name` and `description` are stored separately then the `render` method is used
/// to concatenate them with the correct spacing.
const Description = struct {
    /// For a flag, this is the flag name and the switch, if present.
    /// For a command, this is the command name.
    /// For an enum variant, this is the variant name.
    /// This includes the preceding indentation.
    name: []const u8,
    description: ?[]const u8,

    const help = Description{
        .name = indent ++ "-h, --help",
        .description = "Show this help and exit",
    };

    fn render(comptime self: Description, max_name_len: comptime_int) []const u8 {
        comptime var line = self.name;
        if (self.description) |description| line = line ++
            " " ++ " " ** (max_name_len - self.name.len) ++
            description;

        return line;
    }
};

fn helpCommands(comptime Commands: type, comptime command_name: []const u8) []const u8 {
    comptime var help: []const u8 = std.fmt.comptimePrint(
        // TODO: More specific usage expression.
        "Usage: {s} [command]\n",
        .{command_name},
    );

    if (@hasDecl(Commands, "help")) {
        help = help ++ "\n" ++ Commands.help ++ "\n";
    }

    help = help ++ "\nCommands:\n";

    comptime var descriptions: []const Description = &.{};
    comptime var max_name_len = Description.help.name.len;

    for (std.meta.fields(Commands)) |command| {
        const name = indent ++ format.toKebab(command.name);
        if (name.len > max_name_len) max_name_len = name.len;
        descriptions = descriptions ++ [_]Description{.{
            .name = name,
            .description = getDescriptionFor(Commands, command.name),
        }};
    }

    descriptions = descriptions ++ [_]Description{Description.help};

    for (descriptions) |desc| {
        help = help ++ desc.render(max_name_len) ++ "\n";
    }

    return help;
}

fn helpFlags(comptime Flags: type, comptime command_name: []const u8) []const u8 {
    comptime var help: []const u8 = std.fmt.comptimePrint(
        // TODO: More specific usage expression.
        "Usage: {s} [options]\n",
        .{command_name},
    );

    if (@hasDecl(Flags, "help")) {
        help = help ++ "\n" ++ Flags.help ++ "\n";
    }

    help = help ++ "\nOptions:\n";

    comptime var descriptions: []const Description = &.{};
    comptime var max_name_len = Description.help.name.len;

    for (std.meta.fields(Flags)) |field| {
        comptime var name: []const u8 = format.flagName(field);

        if (comptime getSwitchFor(Flags, field.name)) |swtch| {
            name = std.fmt.comptimePrint(
                "-{c}, {s}",
                .{ swtch, name },
            );
        }

        name = indent ++ name;

        if (name.len > max_name_len) max_name_len = name.len;

        descriptions = descriptions ++ [_]Description{.{
            .name = name,
            .description = getDescriptionFor(Flags, field.name),
        }};

        const T = switch (@typeInfo(field.type)) {
            .Optional => |optional| optional.child,
            else => field.type,
        };

        if (@typeInfo(T) == .Enum) {
            for (std.meta.fields(T)) |enum_field| {
                const variant = .{
                    .name = indent ** 2 ++ format.toKebab(enum_field.name),
                    .description = getDescriptionFor(T, enum_field.name),
                };
                if (variant.name.len > max_name_len) max_name_len = variant.name.len;
                descriptions = descriptions ++ [_]Description{variant};
            }
        }
    }

    descriptions = descriptions ++ [_]Description{Description.help};

    for (descriptions) |desc| {
        help = help ++ desc.render(max_name_len) ++ "\n";
    }

    return help;
}

fn getSwitchFor(comptime Flags: type, comptime name: []const u8) ?u8 {
    if (@hasDecl(Flags, "switches") and
        @hasField(@TypeOf(Flags.switches), name))
    {
        return @field(Flags.switches, name);
    }
    return null;
}

fn getDescriptionFor(comptime Command: type, comptime name: []const u8) ?[]const u8 {
    if (@hasDecl(Command, "descriptions") and
        @hasField(@TypeOf(Command.descriptions), name))
    {
        return @field(Command.descriptions, name);
    }

    return null;
}

test helpMessage {
    const Command = struct {
        pub const help =
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
        \\  -f, --force  Do it more forcefully
        \\  -t, --target Where to aim the laser
        \\  --choice     Pick one
        \\    one        First one
        \\    two        Second one
        \\    three      Third one
        \\  -h, --help   Show this help and exit
        \\
    , comptime helpMessage(Command, "test"));

    const Commands = union(enum) {
        make_a_big_explosion: struct {
            size: u32,
        },

        pub const descriptions = .{
            .make_a_big_explosion = "It's big",
        };
    };

    try std.testing.expectEqualStrings(
        \\Usage: weapons [command]
        \\
        \\Commands:
        \\  make_a_big_explosion It's big
        \\  -h, --help           Show this help and exit
        \\
    , comptime helpMessage(Commands, "weapons"));
}
