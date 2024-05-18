const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("arguments", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_step = b.step("run-example", "Run the specifed example");
    const example_option = b.option(
        enum {
            overview,
            subcommands,
        },
        "example",
        "Example to run for example step (default = overview).",
    ) orelse .overview;
    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{@tagName(example_option)})),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("arguments", mod);
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    example_step.dependOn(&run_example.step);
}
