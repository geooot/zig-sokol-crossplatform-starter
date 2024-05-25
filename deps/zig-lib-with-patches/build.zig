const std = @import("std");

pub fn build(b: *std.Build) void {
    const wf = b.addNamedWriteFiles("zig-lib-patched");
    wf.step.name = "Create Patched Zig Lib";
    const zig = b.dependency("zig", .{});

    // Folders/files to copy over
    // the order of this matters
    _ = wf.addCopyDirectory(zig.path("lib"), "", .{});
    _ = wf.addCopyDirectory(b.path("lib"), "", .{});

    const install_dir = b.addInstallDirectory(.{
        // have to do it this way since in 0.12, WriteFiles doesnt set the path of copied generated directories
        // https://github.com/ziglang/zig/pull/20066
        .source_dir = wf.getDirectory(),

        .install_dir = .lib,
        .install_subdir = "",
    });
    install_dir.step.dependOn(&wf.step);

    b.default_step = &install_dir.step;
}
