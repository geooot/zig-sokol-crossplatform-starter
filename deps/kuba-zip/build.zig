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

    const kubazipc = b.addModule("kubazipc", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = entrypoint,
    });

    kubazipc.addCSourceFile(.{ .file = zipcfile });

    const zipcreate_exe = b.addExecutable(.{
        .name = "zipcreate",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zipcreate.zig"),
    });

    zipcreate_exe.root_module.addImport("kubazipc", kubazipc);

    const zipextract_exe = b.addExecutable(.{
        .name = "zipextract",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zipextract.zig"),
    });

    zipextract_exe.root_module.addImport("kubazipc", kubazipc);

    b.installArtifact(zipcreate_exe);
    b.installArtifact(zipextract_exe);
}
