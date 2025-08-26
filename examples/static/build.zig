const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zinatra = b.dependency("zinatra", .{});

    const exe = b.addExecutable(.{
        .name = "static",
        .root_module = b.createModule(.{
            .root_source_file = b.path("static.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("zinatra", zinatra.module("zinatra"));

    b.installArtifact(exe);
}
