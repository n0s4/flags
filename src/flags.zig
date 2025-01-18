const std = @import("std");

pub const ColorScheme = @import("ColorScheme.zig");
const Parser = @import("Parser.zig");
const Help = @import("Help.zig");

pub const Error = error{
    EmptyArgument,
    /// -h or --help was passed and the help message was printed instead of parsing.
    PrintedHelp,
    StdoutError,
    UnexpectedPositional,
    UnrecognizedFlag,
    UnrecognizedSwitch,
    UnrecognizedArgument,
    MissingValue,
    UnrecognizedOption,
    MissingFlag,
    MissingArgument,
    MissingCommand,
} ||
    std.fmt.ParseIntError ||
    std.fmt.ParseFloatError ||
    std.fs.File.WriteError;

pub const Diagnostics = struct {
    command_name: []const u8,
    help: Help,

    pub fn printHelp(diags: *const Diagnostics, colors: *const ColorScheme) !void {
        const stdout = std.io.getStdOut();
        try diags.help.render(stdout, colors);
    }

    pub fn printUsage(diags: *const Diagnostics, colors: *const ColorScheme) !void {
        const stdout = std.io.getStdOut();
        try diags.help.usage.render(stdout, colors);
    }
};

pub const Options = struct {
    skip_first_arg: bool = true,
    /// Terminal colors used when printing help and error messages. A default theme is provided.
    /// To disable colors completely, pass an empty colorscheme: `&.{}`.
    colors: *const ColorScheme = &.default,
    /// This can be used to access the command name and help message of the command that was being
    /// parsed in case of an error.
    diagnostics: ?*Diagnostics = null,
};

/// Uses `std.posix.exit` to exit with an exit code of 1 in case of an error, and 0 in the case
/// where --help was passed and the help message was printed.
pub fn parseOrExit(
    args: []const [:0]const u8,
    /// The name of your program.
    comptime exe_name: []const u8,
    Flags: type,
    options: Options,
) Flags {
    return parse(args, exe_name, Flags, options) catch |err| switch (err) {
        Error.PrintedHelp => std.posix.exit(0),
        else => std.posix.exit(1),
    };
}

pub fn parse(
    args: []const [:0]const u8,
    /// The name of your program.
    comptime exe_name: []const u8,
    Flags: type,
    options: Options,
) Error!Flags {
    var parser = Parser{
        .args = args,
        .current_arg = if (options.skip_first_arg) 1 else 0,
        .colors = options.colors,
        .diagnostics = options.diagnostics,
    };

    return parser.parse(Flags, exe_name);
}
