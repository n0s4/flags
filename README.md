# Arguments

A powerful, practical command-line argument parser for Zig that won't get in your way.

## Demo

```zig
const std = @import("std");
const arguments = @import("arguments");

const Config = struct {
    // bools and optionals will be set to false/null if their flags are not passed:
    force: bool,
    target: ?[]const u8,

    // non-optional types can have a default, or be required:
    override: []const u8 = "defaulty",
    required: []const u8,

    // ints are parsed automatically:
    age: ?u8,
    power: i32 = 9000,

    // restrict choice with enums:
    use_color: enum { never, auto, always } = .auto,
    job: ?enum { ceo, software_developer, product_manager },

    /// This field is required for storing positional arguments.
    /// A global-scoped fixed buffer is used during parsing to store these to avoid allocation,
    /// this is a slice into that buffer.
    args: []const []const u8,

    /// Optional declaration defines shorthands which can be chained e.g '-ft foo'.
    /// Note that this must be marked `pub`.
    pub const switches = .{
        .force = 'f',
        .target = 't',
        .override = 'o',
        .required = 'r',
        .age = 'a',
        .power = 'p',
        .use_color = 'c',
        .job = 'j',
    };
};

pub fn main() !void {
    var args = std.process.args();

    const result = arguments.parse(&args, Config);

    printConfig(result);
}
```

```
 $ ./path/to/myprogram -fa 21 --required foo --use-color always bar baz
```

## Getting Started

Check out the [import guide](https://github.com/n0s4/Arguments/wiki/Importing) to get set up using Arguments in your project.

## Goals
- [ ] helpful docs
- [ ] decent tests
- [ ] automatic help message generation
- [ ] subcommands
- Support for parsing different types
  - [ ] floats
  - [ ] arrays for a fixed number of arguments (i.e `coordinate: [2]i32` => --coordinate 4 3)

