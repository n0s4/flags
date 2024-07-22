const std = @import("std");
const format = @import("format.zig");
const check = @import("check.zig");

const compileError = check.compileError;
const comptimePrint = std.fmt.comptimePrint;

const indent = "  ";

/// Stores name and description of a field separately
/// `render` is used to concatenate them with the correct spacing.
const Item = struct {
    /// For a flag, this is the flag name and the switch, if present.
    /// For a command, this is the command name.
    /// For an enum variant, this is the variant name.
    /// This includes the preceding indentation.
    name: []const u8,
    description: ?[]const u8,

    const help = Item{
        .name = indent ++ "-h, --help",
        .description = "Show this help and exit",
    };

    fn render(comptime self: Item, max_name_len: comptime_int) []const u8 {
        comptime var line = self.name;
        if (self.description) |description| line = line ++
            " " ++ " " ** (max_name_len - self.name.len) ++
            description;

        return line;
    }
};

pub fn helpMessage(comptime Command: type, comptime name: []const u8) []const u8 {
    comptime if (@hasDecl(Command, "descriptions")) { // validation
        const Descriptions = @TypeOf(Command.descriptions);
        if (@typeInfo(Descriptions) != .Struct) {
            compileError("'descriptions' is not a struct", .{});
        }
        for (std.meta.fields(Descriptions)) |desc| {
            if (!@hasField(Command, desc.name)) {
                compileError("description does not match any field: '{s}'", .{desc.name});
            }
            if (!check.isString(desc.type)) {
                compileError("description is not a string for '{s}'", .{desc.name});
            }
        }
    };

    return switch (@typeInfo(Command)) {
        .Struct => helpFlags(Command, name),
        .Union => helpCommands(Command, name),
        else => comptime unreachable,
    };
}

fn helpCommands(comptime Commands: type, comptime command_name: []const u8) []const u8 {
    comptime var help: []const u8 = comptimePrint(
        // TODO: More specific usage expression.
        "Usage: {s} [command]\n",
        .{command_name},
    );

    if (@hasDecl(Commands, "help")) {
        if (!check.isString(@TypeOf(Commands.help))) {
            compileError("'help' is not a string", .{});
        }
        help = help ++ comptimePrint("\n{s}\n", .{Commands.help});
    }

    help = help ++ "\nCommands:\n\n";

    comptime var items: []const Item = &.{};
    comptime var max_name_len = Item.help.name.len;

    for (std.meta.fields(Commands)) |command| {
        const name = indent ++ format.toKebab(command.name);
        if (name.len > max_name_len) max_name_len = name.len;
        items = items ++ [_]Item{.{
            .name = name,
            .description = getDescriptionFor(Commands, command.name),
        }};
    }

    items = items ++ [_]Item{Item.help};

    for (items) |desc| {
        help = help ++ desc.render(max_name_len) ++ "\n";
    }

    return help;
}

fn helpFlags(comptime Flags: type, comptime command_name: []const u8) []const u8 {
    comptime var help: []const u8 = comptimePrint(
        // TODO: More specific usage expression.
        "Usage: {s} [options]\n",
        .{command_name},
    );

    if (@hasDecl(Flags, "help")) {
        if (!check.isString(@TypeOf(Flags.help))) {
            compileError("'help' is not a string", .{});
        }
        help = help ++ comptimePrint("\n{s}\n", .{Flags.help});
    }

    help = help ++ "\nOptions:\n";

    comptime var descriptions: []const Item = &.{};
    comptime var max_name_len = Item.help.name.len;

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

        descriptions = descriptions ++ [_]Item{.{
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
                descriptions = descriptions ++ [_]Item{variant};
            }
        }
    }

    descriptions = descriptions ++ [_]Item{Item.help};

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
        \\  make-a-big-explosion It's big
        \\  -h, --help           Show this help and exit
        \\
    , comptime helpMessage(Commands, "weapons"));
}
