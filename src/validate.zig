const std = @import("std");

pub fn assertValidConfig(comptime Config: type) void {
    if (@typeInfo(Config) != .Struct) @compileError("Config type must be a struct.");

    inline for (std.meta.fields(Config)) |field| {
        switch (@typeInfo(field.type)) {
            // Allow bool values only outside of optionals
            .Bool => {},
            .Optional => |optional| assertValidFieldType(optional.child, field.name),
            else => assertValidFieldType(field.type, field.name),
        }
    }

    if (@hasDecl(Config, "switches")) {
        const Switches = @TypeOf(Config.switches);
        if (@typeInfo(Switches) != .Struct) {
            @compileError("'switches' must be a struct declaration.");
        }

        const fields = std.meta.fields(Switches);
        inline for (fields, 1..) |field, i| {
            // check for duplicates
            inline for (fields[i..]) |other_field| {
                if (@field(Config.switches, field.name) ==
                    @field(Config.switches, other_field.name))
                {
                    @compileError(std.fmt.comptimePrint(
                        "Duplicated switch values: '{s}' and '{s}'",
                        .{ field.name, other_field.name },
                    ));
                }
            }

            if (!@hasField(Config, field.name)) @compileError(
                "switch name not defined in Config: '" ++ field.name ++ "'",
            );

            const swtch = @field(Config.switches, field.name);
            if (@TypeOf(swtch) != comptime_int) @compileError(
                "switch is not a character: '" ++ field.name ++ "'",
            );
            switch (swtch) {
                'a'...'z', 'A'...'Z' => {},
                else => @compileError(std.fmt.comptimePrint(
                    "switch is not a letter: '{c}'",
                    .{swtch},
                )),
            }
        }
    }
}

fn assertValidFieldType(comptime T: type, comptime field_name: []const u8) void {
    if (T == []const u8) return;

    switch (@typeInfo(T)) {
        .Int => return,
        .Enum => |e| if (e.is_exhaustive) return,

        else => {}, // fallthrough to compileError.
    }

    @compileError(std.fmt.comptimePrint(
        "Bad Config field type '{s}': {s}.",
        .{ field_name, @typeName(T) },
    ));
}
