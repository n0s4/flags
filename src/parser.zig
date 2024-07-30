const std = @import("std");
const meta = @import("meta.zig");
const core = @import("core.zig");

pub const TrailingHandler = core.TrailingHandler;
pub const fatal = core.fatal;

const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;

pub const ParseOptions = struct {
    /// The first argument is almost always the executable name used to run the program.
    skip_first_arg: bool = true,
    /// The name of the command used to run the program, should be your executable name.
    /// If omitted, the name of the Command type will be used.
    command_name: ?[]const u8 = null,
};

/// A TrailingHandler that causes a fatal error when a trailing argument is passed.
const NoTrailing = struct {
    pub const NoError = error{};

    fn errorOnTrailing(context: *anyopaque, arg: []const u8) NoError!void {
        _ = context;
        fatal("unexpected argument: '{s}'", .{arg});
    }

    pub fn handler() TrailingHandler {
        return .{
            .context = undefined,
            .handleFn = &errorOnTrailing,
        };
    }
};

/// This does not allow any trailing arguments to be passed.
/// If you need to take trailing arguments, use `parseWithBuffer` or `parseWithAllocator`.
pub fn parse(args: *ArgIterator, comptime Command: type, comptime options: ParseOptions) Command {
    return parseWithTrailingHandler(
        NoTrailing.handler(),
        args,
        Command,
        options,
    ) catch unreachable;
}

/// Combines `Command` with an `args` field which stores trailing arguments.
fn Result(comptime Command: type) type {
    return struct {
        command: Command,
        trailing: []const []const u8,
    };
}

/// A TrailingHandler which appends trailing arguments in a fixed buffer.
const FixedBufferList = struct {
    const Error = Allocator.Error;

    buffer: [][]const u8,
    len: usize = 0,

    fn append(self: *FixedBufferList, arg: []const u8) Error!void {
        if (self.len >= self.buffer.len) {
            return Error.OutOfMemory;
        }
        self.buffer[self.len] = arg;
        self.len += 1;
    }

    fn appendTypeErased(context: *anyopaque, arg: []const u8) Error!void {
        const self: *FixedBufferList = @alignCast(@ptrCast(context));
        return self.append(arg);
    }

    pub fn handler(self: *FixedBufferList) TrailingHandler {
        return .{
            .context = self,
            .handleFn = &appendTypeErased,
        };
    }
};

/// Uses a fixed buffer to store trailing arguments.
/// Fails if the number of trailing arguments passed cannot fit in the buffer.
pub fn parseWithBuffer(
    trailing_args_buf: [][]const u8,
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) Allocator.Error!Result(Command) {
    var trailing = FixedBufferList{ .buffer = trailing_args_buf };

    // Error-casting nightmare because trailing.write returns anyerror.
    const command = try @as(
        Allocator.Error!Command,
        @errorCast(
            parseWithTrailingHandler(
                trailing.handler(),
                args,
                Command,
                options,
            ),
        ),
    );

    return Result(Command){
        .command = command,
        .trailing = trailing.buffer[0..trailing.len],
    };
}

/// Combines the `Command` result with an allocated list of trailing arguments.
pub fn AllocResult(comptime Command: type) type {
    return struct {
        command: Command,
        trailing: std.ArrayList([]const u8),
    };
}

/// TrailingHandler appending trailing arguments to a `std.ArrayList`.
const AllocatedList = struct {
    pub const Error = Allocator.Error;

    list: std.ArrayList([]const u8),

    fn appendTypeErased(context: *anyopaque, arg: []const u8) Error!void {
        const self: *AllocatedList = @alignCast(@ptrCast(context));
        return self.list.append(arg);
    }

    fn handler(self: *AllocatedList) TrailingHandler {
        return .{
            .context = self,
            .handleFn = &appendTypeErased,
        };
    }
};

/// Call result.args.deinit() to free the trailing arguments.
pub fn parseWithAllocator(
    allocator: Allocator,
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) Allocator.Error!AllocResult(Command) {
    var trailing = AllocatedList{ .list = std.ArrayList([]const u8).init(allocator) };

    const command = try @as(
        Allocator.Error!Command,
        @errorCast(
            parseWithTrailingHandler(
                trailing.handler(),
                args,
                Command,
                options,
            ),
        ),
    );

    return AllocResult(Command){
        .command = command,
        .trailing = trailing.list,
    };
}

/// The returned error will originate from the trailing_handler's handle function.
pub fn parseWithTrailingHandler(
    trailing_handler: TrailingHandler,
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) !Command {
    if (options.skip_first_arg) {
        if (!args.skip()) fatal("expected at least 1 argument", .{});
    }

    const command_name = options.command_name orelse comptime commandName(Command);
    return core.parse(args, Command, command_name, trailing_handler);
}

// Converts Type name "namespace.MyCommand" to "my-command"
fn commandName(comptime Command: type) []const u8 {
    comptime var base_name: []const u8 = @typeName(Command);
    // Trim off the leading namespaces - separated by dots.
    if (std.mem.lastIndexOfScalar(u8, base_name, '.')) |last_dot_idx| {
        base_name = base_name[last_dot_idx + 1 ..];
    }

    comptime var cmd_name: []const u8 = &.{std.ascii.toLower(base_name[0])};
    for (base_name[1..]) |ch| {
        cmd_name = cmd_name ++ if (std.ascii.isUpper(ch))
            .{ '-', std.ascii.toLower(ch) }
        else
            .{ch};
    }

    return cmd_name;
}
