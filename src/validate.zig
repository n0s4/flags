const std = @import("std");

fn compileError(comptime fmt: []const u8, args: anytype) void {
    @compileError("flags: " ++ std.fmt.comptimePrint(fmt, args));
}

/// Checks whether T is the type of a compile-time string literal.
/// String literals have the type *const [len:0]u8
fn isString(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .Pointer) return false;
    const child = @typeInfo(info.Pointer.child);
    return child == .Array and
        child.Array.child == u8;
}

pub fn assertValid(comptime Command: type) void {
    if (!@hasDecl(Command, "name")) {
        compileError("top-level command does not declare a name", {});
    }
    if (comptime !isString(@TypeOf(Command.name))) {
        compileError("'name' declaration is not a string", .{});
    }
    assertValidGeneric(Command);
}

fn assertValidGeneric(comptime Command: type) void {
    switch (@typeInfo(Command)) {
        .Struct => assertValidFlags(Command),
        .Union => assertValidCommands(Command),
        else => compileError("command must be a struct or union type", .{}),
    }
}

fn assertValidCommands(comptime Commands: type) void {
    if (@hasDecl(Commands, "descriptions")) {
        assertValidDescriptions(Commands, Commands.descriptions);
    }
    inline for (std.meta.fields(Commands)) |field| {
        assertValidGeneric(field.type);
    }
}

fn assertValidFlags(comptime Flags: type) void {
    inline for (std.meta.fields(Flags)) |field| {
        if (comptime std.mem.eql(u8, "help", field.name)) {
            compileError("flag name 'help' is reserved for showing usage", {});
        }
        switch (@typeInfo(field.type)) {
            // Allow bool values only outside of optionals
            .Bool => {},
            .Optional => |optional| assertValidFlag(optional.child, field.name),
            else => assertValidFlag(field.type, field.name),
        }
    }

    if (@hasDecl(Flags, "switches")) {
        assertValidSwitches(Flags, Flags.switches);
    }

    if (@hasDecl(Flags, "descriptions")) {
        assertValidDescriptions(Flags, Flags.descriptions);
    }
}

fn assertValidSwitches(comptime Flags: type, switches: anytype) void {
    const Switches = @TypeOf(switches);
    if (@typeInfo(Switches) != .Struct) {
        compileError("'switches' is not a struct declaration", .{});
    }

    const fields = std.meta.fields(Switches);
    inline for (fields, 0..) |field, i| {
        if (!@hasField(Flags, field.name)) compileError(
            "switch name does not match any field: '{s}'",
            .{field.name},
        );

        const swtch = @field(Flags.switches, field.name);
        if (@TypeOf(swtch) != comptime_int) compileError(
            "switch is not a character: '{s}'",
            .{field.name},
        );

        switch (swtch) {
            'a'...'z', 'A'...'Z' => {
                if (swtch == 'h') {
                    compileError("switch '-h' is reserved for showing usage", .{});
                }
            },
            else => compileError(
                "switch is not a letter: '{c}'",
                .{swtch},
            ),
        }

        inline for (fields[i + 1 ..]) |other_field| {
            if (swtch == @field(switches, other_field.name)) {
                compileError(
                    "duplicated switch values: '{s}' and '{s}'",
                    .{ field.name, other_field.name },
                );
            }
        }
    }
}

fn assertValidDescriptions(comptime Flags: type, descriptions: anytype) void {
    const Descriptions = @TypeOf(descriptions);
    if (@typeInfo(Descriptions) != .Struct) {
        compileError("'descriptions' is not a struct declaration", {});
    }
    inline for (std.meta.fields(Descriptions)) |field| {
        if (!@hasField(Flags, field.name)) compileError(
            "description name does not match any field: '{s}'",
            .{field.name},
        );

        const desc = @field(Flags.descriptions, field.name);
        if (comptime !isString(@TypeOf(desc))) {
            compileError("description is not a string: '{s}'", .{field.name});
        }
    }
}

fn assertValidFlag(comptime T: type, comptime field_name: []const u8) void {
    if (T == []const u8) return;

    switch (@typeInfo(T)) {
        .Int => return,
        .Enum => |e| {
            if (@hasDecl(T, "descriptions")) {
                assertValidDescriptions(T, T.descriptions);
            }
            if (e.is_exhaustive) return;
        },

        else => {}, // fallthrough to compileError.
    }

    compileError(
        "bad flag type '{s}': {s}",
        .{ field_name, @typeName(T) },
    );
}
