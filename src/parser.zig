const std = @import("std");
const meta = @import("meta.zig");
const core = @import("core.zig");
const help = @import("help.zig");

pub const TrailingHandler = core.TrailingHandler;
pub const printError = core.printError;

const ArgIterator = std.process.ArgIterator;
const Allocator = std.mem.Allocator;

pub const ParseOptions = struct {
    /// The first argument is almost always the executable name used to run the program.
    skip_first_arg: bool = true,
    /// The name of the command used to run the program, should be your executable name.
    /// If omitted, the name of the Command type will be used.
    command_name: ?[]const u8 = null,
};

/// A TrailingHandler that causes a printError error when a trailing argument is passed.
const NoTrailing = struct {
    fn errorOnTrailing(context: *anyopaque, arg: []const u8) !void {
        _ = context;
        printError("unexpected argument: '{s}'", .{arg});
        return error.BadArgument;
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
pub fn parse(args: *ArgIterator, comptime Command: type, comptime options: ParseOptions) !Command {
    return parseWithTrailingHandler(
        NoTrailing.handler(),
        args,
        Command,
        options,
    );
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
    const command_name = options.command_name orelse comptime meta.commandName(Command);

    if (options.skip_first_arg) {
        if (!args.skip()) {
            printError("expected at least 1 argument", .{});
            try help.printUsage(Command, command_name, std.io.getStdOut().writer());
            return error.NoArguments;
        }
    }

    return core.parse(args, Command, command_name, trailing_handler);
}
