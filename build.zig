const std = @import("std");
const Build = std.build;
const sokol = @import("deps/sokol-zig/build.zig");

const APP_NAME = "MyApp";

pub fn build(b: *Build.Builder) !void {
    // targets
    const default_target = b.standardTargetOptions(.{});
    const native_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "native" });
    const ios_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "aarch64-ios" });
    const ios_sim_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = if (native_target.getCpuArch().isAARCH64()) "aarch64-ios-simulator" else "x86_64-ios-simulator" });

    const optimize = b.standardOptimizeOption(.{});

    // libraries
    const ios_build_lib = try buildAppLib(b, ios_target, optimize);
    const ios_sokol_lib = try buildSokolLib(b, ios_target, optimize);

    const ios_sim_build_lib = try buildAppLib(b, ios_sim_target, optimize);
    const ios_sim_sokol_lib = try buildSokolLib(b, ios_sim_target, optimize);

    const default_build_lib = try buildAppLib(b, default_target, optimize);
    const default_sokol_lib = try buildSokolLib(b, default_target, optimize);
    const default_exe = try buildExe(b, default_target, optimize, default_sokol_lib, default_build_lib);
    const install_default_exe = b.addInstallArtifact(default_exe, .{});

    const ios_build_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_build_lib.dest_sub_path });
    const ios_sim_build_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_sim_build_lib.dest_sub_path });
    const ios_sokol_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_sokol_lib.dest_sub_path });
    const ios_sim_sokol_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_sim_sokol_lib.dest_sub_path });
    const ios_app_framework_install_path = b.pathJoin(&.{ b.lib_dir, "ios_lib" ++ APP_NAME ++ ".xcframework" });
    const ios_sokol_framework_install_path = b.pathJoin(&.{ b.lib_dir, "ios_libsokol.xcframework" });

    // generate iOS framework files
    const delete_old_framework_files = b.addSystemCommand(&.{ "rm", "-rf", ios_app_framework_install_path, ios_sokol_framework_install_path });

    const generate_ios_app_framework = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework", "-library", ios_build_lib_install_path, "-library", ios_sim_build_lib_install_path, "-output", ios_app_framework_install_path });
    generate_ios_app_framework.step.dependOn(&ios_build_lib.step);
    generate_ios_app_framework.step.dependOn(&ios_sim_build_lib.step);
    generate_ios_app_framework.step.dependOn(&delete_old_framework_files.step);
    const generate_ios_sokol_framework = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework", "-library", ios_sokol_lib_install_path, "-library", ios_sim_sokol_lib_install_path, "-output", ios_sokol_framework_install_path });
    generate_ios_sokol_framework.step.dependOn(&ios_sokol_lib.step);
    generate_ios_sokol_framework.step.dependOn(&ios_sim_sokol_lib.step);
    generate_ios_sokol_framework.step.dependOn(&delete_old_framework_files.step);

    // generate xcode project
    const project_yml_loc = b.pathJoin(&.{ "ios", "project.yml" });
    const generate_xcode_proj = b.addSystemCommand(&.{ "xcodegen", "generate", "--spec" });
    generate_xcode_proj.addFileArg(.{ .path = project_yml_loc });
    generate_xcode_proj.addArg("--project");
    generate_xcode_proj.addDirectoryArg(.{ .path = b.install_prefix });
    generate_xcode_proj.setEnvironmentVariable("APP_LIB", ios_app_framework_install_path);
    generate_xcode_proj.setEnvironmentVariable("SOKOL_LIB", ios_sokol_framework_install_path);
    generate_xcode_proj.setEnvironmentVariable("APP_NAME", APP_NAME);
    generate_xcode_proj.expectExitCode(0);

    // build iOS app with xcodebuild and the generated xcode project
    const xcodebuild = b.addSystemCommand(&.{ "xcodebuild", "-project", b.pathJoin(&.{ b.install_prefix, APP_NAME ++ ".xcodeproj" }), "-target", APP_NAME });
    xcodebuild.step.dependOn(&generate_xcode_proj.step);
    xcodebuild.step.dependOn(&generate_ios_app_framework.step);
    xcodebuild.step.dependOn(&generate_ios_sokol_framework.step);

    // entrypoint build steps
    const install_ios = b.step("ios", "Build iOS project");
    install_ios.dependOn(&xcodebuild.step);

    const install_default = b.step("default", "Build binaries for the current system (or specified in command)");
    install_default.dependOn(&install_default_exe.step);

    const run_exe = b.addRunArtifact(default_exe);
    const run_step = b.step("run", "Run project");
    run_step.dependOn(&run_exe.step);

    const allStep = b.step("all", "Build everything");
    allStep.dependOn(install_default);
    allStep.dependOn(install_ios);

    b.default_step = allStep;
}

fn buildExe(b: *Build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, sokol_lib: *Build.Step.InstallArtifact, app_lib: *Build.Step.InstallArtifact) !*Build.CompileStep {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});
    const exe = b.addExecutable(.{ .name = name, .target = target, .optimize = optimize });
    exe.linkLibrary(app_lib.artifact);
    exe.linkLibrary(sokol_lib.artifact);
    return exe;
}

fn buildAppLib(b: *Build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) !*Build.Step.InstallArtifact {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});

    const lib = b.addStaticLibrary(.{ .name = name, .target = target, .optimize = optimize, .root_source_file = .{ .path = "core/main.zig" } });
    const sokol_module = b.addModule("sokol", .{ .source_file = .{ .path = "deps/sokol-zig/src/sokol/sokol.zig" } });
    lib.addModule("sokol", sokol_module);
    const install_lib = b.addInstallArtifact(lib, .{});

    return install_lib;
}

fn buildSokolLib(b: *Build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) !*Build.Step.InstallArtifact {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt("libsokol" ++ "_{s}.a", .{triple});

    const lib = sokol.buildSokol(b, target, optimize, .{}, "deps/sokol-zig/");
    try addIOSCompilePaths(b, target, lib);
    const install_lib = b.addInstallArtifact(lib, .{ .dest_sub_path = name });

    return install_lib;
}

fn addIOSCompilePaths(b: *Build.Builder, target: std.zig.CrossTarget, step: *Build.CompileStep) !void {
    if (target.os_tag == .ios) {
        const native_target = try std.zig.system.NativeTargetInfo.detect(target);
        const sysroot = std.zig.system.darwin.getSdk(b.allocator, native_target.target);
        step.addLibraryPath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/usr/lib" }) }); //(.{ .cwd_relative = "/usr/lib" });
        step.addIncludePath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/usr/include" }) }); //(.{ .cwd_relative = "/usr/include" });
        step.addFrameworkPath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/System/Library/Frameworks" }) }); //(.{ .cwd_relative = "/System/Library/Frameworks" });
    }
}
