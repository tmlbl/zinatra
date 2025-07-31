const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const zinatra = b.addModule("zinatra", .{
        .root_source_file = .{ .cwd_relative = "../../src/App.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "tls",
        .root_source_file = b.path("tls.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("openssl");

    exe.root_module.addImport("zinatra", zinatra);

    b.installArtifact(exe);
}
