const std = @import("std");
const validate = @import("validate.zig");
const core = @import("core.zig");

pub const PositionalHandler = core.PositionalHandler;
pub const fatal = core.fatal;

const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;

pub const ParseOptions = struct {
    /// The first argument is almost always the executable name used to run the program.
    skip_first_arg: bool = true,

    /// Give useful compile errors if your `Command` type is invalid.
    ///
    /// Only disable if you don't need help and want to save the compiler from unnecessary work.
    validate: bool = true,
};

/// A PositionalHandler that causes a fatal error when a positional argument is passed.
const NoPositional = struct {
    pub const NoError = error{};

    fn errorOnPositional(context: *anyopaque, positional: []const u8) NoError!void {
        _ = context;
        fatal("unexpected argument: '{s}'", .{positional});
    }

    pub fn handler() PositionalHandler(NoError) {
        return .{
            .context = undefined,
            .handleFn = &errorOnPositional,
        };
    }
};

/// This does not allow any positional arguments to be passed.
/// If you need to take positional arguments, use `parseWithBuffer` or `parseWithAllocator`.
pub fn parse(args: *ArgIterator, comptime Command: type, comptime options: ParseOptions) Command {
    return parseWithPositionalHandler(
        NoPositional.NoError,
        NoPositional.handler(),
        args,
        Command,
        options,
    ) catch unreachable;
}

/// Combines `Command` with an `args` field which stores positional arguments.
fn Result(comptime Command: type) type {
    return struct {
        command: Command,
        positionals: []const []const u8,
    };
}

/// A PositionalHandler which appends positionals in a fixed buffer.
const FixedBufferList = struct {
    pub const Error = Allocator.Error;

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

    pub fn handler(self: *FixedBufferList) PositionalHandler(Error) {
        return .{
            .context = self,
            .handleFn = &appendTypeErased,
        };
    }
};

/// Uses a fixed buffer to store positional/trailing arguments.
/// Fails if the number of positional arguments passed cannot fit in the buffer.
pub fn parseWithBuffer(
    positional_args_buf: [][]const u8,
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) Allocator.Error!Result(Command) {
    var positionals = FixedBufferList{ .buffer = positional_args_buf };

    const command = try parseWithPositionalHandler(
        FixedBufferList.Error,
        positionals.handler(),
        args,
        Command,
        options,
    );

    return Result(Command){
        .command = command,
        .positionals = positionals.buffer[0..positionals.len],
    };
}

/// Combines the `Command` result with an allocated list of positional arguments.
pub fn AllocResult(comptime Command: type) type {
    return struct {
        command: Command,
        positionals: std.ArrayList([]const u8),
    };
}

/// PositionalHandler appending positionals to a `std.ArrayList`.
const AllocatedList = struct {
    pub const Error = Allocator.Error;

    list: std.ArrayList([]const u8),

    fn appendTypeErased(context: *anyopaque, arg: []const u8) Error!void {
        const self: *AllocatedList = @alignCast(@ptrCast(context));
        return self.list.append(arg);
    }

    fn handler(self: *AllocatedList) PositionalHandler(Error) {
        return .{
            .context = self,
            .handleFn = &appendTypeErased,
        };
    }
};

/// Call result.args.deinit() to free the positional arguments.
pub fn parseWithAllocator(
    allocator: Allocator,
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) Allocator.Error!AllocResult(Command) {
    var positionals = AllocatedList{ .list = std.ArrayList([]const u8).init(allocator) };

    const command = try parseWithPositionalHandler(
        AllocatedList.Error,
        positionals.handler(),
        args,
        Command,
        options,
    );

    return AllocResult(Command){
        .command = command,
        .positionals = positionals.list,
    };
}

pub fn parseWithPositionalHandler(
    comptime HandleError: type,
    pos_handler: PositionalHandler(HandleError),
    args: *ArgIterator,
    comptime Command: type,
    comptime options: ParseOptions,
) HandleError!Command {
    if (options.validate) {
        comptime validate.assertValid(Command);
    }
    if (options.skip_first_arg) {
        if (!args.skip()) fatal("expected at least 1 argument", .{});
    }

    return core.parse(args, Command, Command.name, HandleError, pos_handler);
}
