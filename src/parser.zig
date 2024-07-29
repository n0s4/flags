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

    comptime if (!@hasDecl(Command, "name") or !meta.isString(@TypeOf(Command.name))) {
        meta.compileError("top level command must declare a 'name' as a string", .{});
    };
    return core.parse(args, Command, Command.name, trailing_handler);
}
