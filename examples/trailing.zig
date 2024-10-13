const std = @import("std");
const flags = @import("flags");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    var trailing_args = std.ArrayList([]const u8).init(gpa.allocator());
    defer trailing_args.deinit();

    _ = flags.parseOrExit(&args, "trailing-args", Flags, .{
        .trailing_list = &trailing_args,
    });

    for (trailing_args.items, 0..) |arg, i| {
        std.debug.print("{d}: {s}\n", .{ i, arg });
    }
}

const Flags = struct {
    flag: bool,
};
