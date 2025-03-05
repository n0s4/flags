# flags

An effortless command-line argument parser for Zig.

## Features

- Zero allocations.
- Cross platform.
- Single-function, declarative API.
- Multi-level subcommands.
- Automatic help message generation at comptime.
- Customisable terminal coloring.

## Getting Started

To import flags to your project, run the following command:

```
zig fetch --save git+https://github.com/n0s4/flags
```

Then set up the dependency in your `build.zig`:

```zig
    const flags_dep = b.dependency("flags", .{
        .target = target,
        .optimize = optimize,
    })

    exe.root_module.addImport("flags", flags_deb.module("flags"));
```

See the [examples](examples/) for basic usage.
