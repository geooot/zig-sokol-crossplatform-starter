const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const kubazipc_dep = b.dependency("kubazipc", .{
        .target = target,
        .optimize = optimize,
    });

    const zipcfile = kubazipc_dep.path("src/zip.c");
    const ziphfile = kubazipc_dep.path("src/zip.h");

    const translateC = b.addTranslateC(.{
        .root_source_file = ziphfile,
        .target = target,
        .optimize = optimize,
    });
    const entrypoint = translateC.getOutput();

    const kubazipc = b.addModule("kubazip", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = entrypoint,
    });

    kubazipc.addCSourceFile(.{ .file = zipcfile });

    const exe = b.addExecutable(.{
        .name = "zipcreate",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/zip.zig" },
    });

    exe.root_module.addImport("kubazip", kubazipc);

    b.installArtifact(exe);
}
