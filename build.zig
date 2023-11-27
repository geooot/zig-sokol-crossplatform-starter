const std = @import("std");
const Build = std.build;
const sokol = @import("deps/sokol-zig/build.zig");
const auto_detect = @import("build/auto-detect.zig");
const ListFiles = @import("build/ListFiles.zig");

const APP_NAME = "MyApp";
const BUNDLE_PREFIX = "com.example";

const ANDROID_TARGET_API_VERSION = "32";
const ANDROID_MIN_API_VERSION = "32";
const ANDROID_BUILD_TOOLS_VERSION = "34.0.0";
const ANDROID_NDK_VERSION = "26.1.10909125";

const ANDROID_KEYSTORE_ALIAS = "androidkey";
const ANDROID_KEYSTORE_DNAME_STRING = "CN=Unknown, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=Unknown";
const ANDROID_KEYSTORE_KEYPASS = "android";

pub fn build(b: *Build.Builder) !void {
    // targets
    const default_target = b.standardTargetOptions(.{});
    const native_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "native" });
    const ios_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "aarch64-ios" });
    const ios_sim_target = try std.zig.CrossTarget.parse(.{
        .arch_os_abi = if (native_target.getCpuArch().isAARCH64()) "aarch64-ios-simulator" else "x86_64-ios-simulator",
    });
    const android_arm64_target = try std.zig.CrossTarget.parse(.{
        .arch_os_abi = "aarch64-linux-android",
        .cpu_features = "baseline+v8a",
    });
    const optimize = b.standardOptimizeOption(.{});

    const android_sdk = try auto_detect.findAndroidSDKConfig(b, &android_arm64_target, .{
        .api_version = ANDROID_TARGET_API_VERSION,
        .build_tools_version = ANDROID_BUILD_TOOLS_VERSION,
        .ndk_version = ANDROID_NDK_VERSION,
    });

    const generate_libc_file = try createLibCFile(b, .{
        .include_dir = android_sdk.android_ndk_include_host,
        .sys_include_dir = android_sdk.android_ndk_include_host_arch_android,
        .crt_dir = android_sdk.android_ndk_lib_host_arch_android,
    });

    // libraries
    const ios_build_lib = try buildAppLib(b, ios_target, optimize);
    const ios_sokol_lib = try buildSokolLib(b, ios_target, optimize);

    const ios_sim_build_lib = try buildAppLib(b, ios_sim_target, optimize);
    const ios_sim_sokol_lib = try buildSokolLib(b, ios_sim_target, optimize);

    const android_build_lib = try buildAppLib(b, android_arm64_target, optimize);
    const android_sokol_lib = try buildSokolLib(b, android_arm64_target, optimize);

    const android_combo_lib = try buildComboLib(
        b,
        android_arm64_target,
        optimize,
        android_sokol_lib,
        android_build_lib,
    );

    android_combo_lib.step.dependOn(&generate_libc_file.step);
    android_combo_lib.artifact.setLibCFile(generate_libc_file.files.getLast().getPath());

    const default_build_lib = try buildAppLib(b, default_target, optimize);
    const default_sokol_lib = try buildSokolLib(b, default_target, optimize);

    const ios_build_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_build_lib.dest_sub_path });
    const ios_sim_build_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_sim_build_lib.dest_sub_path });
    const ios_sokol_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_sokol_lib.dest_sub_path });
    const ios_sim_sokol_lib_install_path = b.pathJoin(&.{ b.lib_dir, ios_sim_sokol_lib.dest_sub_path });
    const ios_app_framework_install_path = b.pathJoin(&.{ b.lib_dir, "ios_lib" ++ APP_NAME ++ ".xcframework" });
    const ios_sokol_framework_install_path = b.pathJoin(&.{ b.lib_dir, "ios_libsokol.xcframework" });

    // generate iOS framework files
    const delete_old_framework_files = b.addSystemCommand(
        &.{ "rm", "-rf", ios_app_framework_install_path, ios_sokol_framework_install_path },
    );

    const generate_ios_app_framework = b.addSystemCommand(&.{
        "xcodebuild",
        "-create-xcframework",
        "-library",
        ios_build_lib_install_path,
        "-library",
        ios_sim_build_lib_install_path,
        "-output",
        ios_app_framework_install_path,
    });
    generate_ios_app_framework.step.dependOn(&ios_build_lib.step);
    generate_ios_app_framework.step.dependOn(&ios_sim_build_lib.step);
    generate_ios_app_framework.step.dependOn(&delete_old_framework_files.step);
    const generate_ios_sokol_framework = b.addSystemCommand(&.{
        "xcodebuild",
        "-create-xcframework",
        "-library",
        ios_sokol_lib_install_path,
        "-library",
        ios_sim_sokol_lib_install_path,
        "-output",
        ios_sokol_framework_install_path,
    });
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
    generate_xcode_proj.setEnvironmentVariable("BUNDLE_PREFIX", BUNDLE_PREFIX);
    generate_xcode_proj.expectExitCode(0);
    generate_xcode_proj.step.dependOn(&generate_ios_app_framework.step);
    generate_xcode_proj.step.dependOn(&generate_ios_sokol_framework.step);

    // !! can't build since no team specified in xcode project !!

    // // build iOS app with xcodebuild and the generated xcode project
    // const xcodebuild = b.addSystemCommand(
    //     &.{ "xcodebuild", "-project", b.pathJoin(&.{ b.install_prefix, APP_NAME ++ ".xcodeproj" }), "-target", APP_NAME },
    // );
    // xcodebuild.step.dependOn(&generate_xcode_proj.step);
    // xcodebuild.step.dependOn(&generate_ios_app_framework.step);
    // xcodebuild.step.dependOn(&generate_ios_sokol_framework.step);

    // android
    const install_keystore = generateAndroidKeyStore(b);

    var permissions = std.ArrayList([]const u8).init(b.allocator);
    try permissions.append("android.permission.SET_RELEASE_APP");
    try permissions.append("android.permission.INTERNET");
    try permissions.append("android.permission.ACCESS_NETWORK_STATE");
    const generate_android_manifest = try generateAndroidManifest(
        b,
        .{ .package = BUNDLE_PREFIX ++ "." ++ APP_NAME, .lib_name = android_combo_lib.artifact.name, .permissions = permissions },
    );
    generate_android_manifest.step.dependOn(&android_combo_lib.step);
    const generate_compiled_resources = generateAndroidCompiledResources(b, generate_android_manifest, &android_sdk);
    const generate_android_pre_bundle = generateAndroidPreBundle(b, generate_android_manifest, generate_compiled_resources, &android_sdk, ANDROID_TARGET_API_VERSION);
    const generate_second_android_pre_bundle = generateAndroidAppSecondPreBundle(b, generate_android_pre_bundle, android_combo_lib);
    const generate_android_bundle = generateAndroidAppBundle(b, generate_second_android_pre_bundle);
    const generate_android_apks = generateAndroidApks(b, install_keystore, generate_android_bundle);

    // native build exe
    const default_exe = try buildExe(b, default_target, optimize, default_sokol_lib, default_build_lib);
    const install_default_exe = b.addInstallArtifact(default_exe, .{});

    // entrypoint build steps
    const install_ios = b.step("ios", "Setup iOS project");
    install_ios.dependOn(&generate_xcode_proj.step);

    const install_default = b.step("default", "Build binaries for the current system (or specified in command)");
    install_default.dependOn(&install_default_exe.step);

    const install_android = b.step("android", "Build android project");
    install_android.dependOn(&generate_android_apks.step);

    const run_exe = b.addRunArtifact(default_exe);
    const run_step = b.step("run", "Run project");
    run_step.dependOn(&run_exe.step);

    const all_step = b.step("all", "Build everything");
    all_step.dependOn(install_default);
    all_step.dependOn(install_ios);
    all_step.dependOn(install_android);

    b.default_step = all_step;
}

fn buildExe(b: *Build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, sokol_lib: *Build.Step.InstallArtifact, app_lib: *Build.Step.InstallArtifact) !*Build.CompileStep {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});
    const exe = b.addExecutable(.{ .name = name, .target = target, .optimize = optimize });
    exe.linkLibrary(app_lib.artifact);
    exe.linkLibrary(sokol_lib.artifact);
    return exe;
}

fn buildAppLib(
    b: *Build.Builder,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) !*Build.Step.InstallArtifact {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});

    const lib = b.addStaticLibrary(.{ .name = name, .target = target, .optimize = optimize, .root_source_file = .{ .path = "core/main.zig" } });
    const sokol_module = b.addModule("sokol", .{ .source_file = .{ .path = "deps/sokol-zig/src/sokol/sokol.zig" } });
    lib.addModule("sokol", sokol_module);
    const install_lib = b.addInstallArtifact(lib, .{});

    return install_lib;
}

fn buildSokolLib(
    b: *Build.Builder,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) !*Build.Step.InstallArtifact {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt("libsokol" ++ "_{s}.a", .{triple});

    const lib = sokol.buildSokol(b, target, optimize, .{}, "deps/sokol-zig/");
    lib.defineCMacro("SOKOL_REMOVE_MAIN_STUB", "1");
    try addCompilePaths(b, target, lib);
    const install_lib = b.addInstallArtifact(lib, .{ .dest_sub_path = name });

    return install_lib;
}

fn buildComboLib(
    b: *Build.Builder,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    sokol_lib: *Build.Step.InstallArtifact,
    app_lib: *Build.Step.InstallArtifact,
) !*Build.Step.InstallArtifact {
    const triple = try target.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_withsokol_{s}", .{triple});

    const lib = b.addSharedLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibrary(sokol_lib.artifact);
    lib.linkLibrary(app_lib.artifact);
    try addCompilePaths(b, target, lib);

    const install_lib = b.addInstallArtifact(lib, .{});
    return install_lib;
}

fn addCompilePaths(b: *Build.Builder, target: std.zig.CrossTarget, step: *Build.CompileStep) !void {
    const native_target_info = try std.zig.system.NativeTargetInfo.detect(target);
    if (native_target_info.target.os.tag == .ios) {
        const sysroot = std.zig.system.darwin.getSdk(b.allocator, native_target_info.target) orelse b.sysroot;
        step.addLibraryPath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/usr/lib" }) }); //(.{ .cwd_relative = "/usr/lib" });
        step.addIncludePath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/usr/include" }) }); //(.{ .cwd_relative = "/usr/include" });
        step.addFrameworkPath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/System/Library/Frameworks" }) }); //(.{ .cwd_relative = "/System/Library/Frameworks" });
    } else if (native_target_info.target.isAndroid()) {
        const target_dir_name = switch (native_target_info.target.cpu.arch) {
            .aarch64 => "aarch64-linux-android",
            .x86_64 => "x86_64-linux-android",
            else => @panic("unsupported arch for android build"),
        };
        _ = target_dir_name;

        const android_sdk = try auto_detect.findAndroidSDKConfig(b, &target, .{
            .api_version = ANDROID_TARGET_API_VERSION,
            .build_tools_version = ANDROID_BUILD_TOOLS_VERSION,
            .ndk_version = ANDROID_NDK_VERSION,
        });

        step.addIncludePath(.{ .path = android_sdk.android_ndk_include });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_android });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_host });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_host_android });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_host_arch_android });

        step.defineCMacro("ANDROID", null);
        step.linkLibC();

        step.addLibraryPath(.{ .path = android_sdk.android_ndk_lib_host_arch_android });
    }
}

// Based off of https://github.com/MasterQ32/ZigAndroidTemplate/blob/master/Sdk.zig#L906
const LibCFileConfig = struct {
    include_dir: []const u8 = "",
    sys_include_dir: []const u8 = "",
    crt_dir: []const u8 = "",
};
fn createLibCFile(b: *Build.Builder, config: LibCFileConfig) !*Build.Step.WriteFile {
    const create_lib_c_file = b.addWriteFile("android.conf", blk: {
        var buf = std.ArrayList(u8).init(b.allocator);

        errdefer buf.deinit();

        var writer = buf.writer();

        @setEvalBranchQuota(1_000_000);

        try writer.print("include_dir={s}\n", .{config.include_dir});
        try writer.print("sys_include_dir={s}\n", .{config.sys_include_dir});
        try writer.print("crt_dir={s}\n", .{config.crt_dir});
        try writer.print("msvc_lib_dir=\n", .{});
        try writer.print("kernel32_lib_dir=\n", .{});
        try writer.print("gcc_dir=\n", .{});
        break :blk buf.toOwnedSlice() catch unreachable;
    });
    create_lib_c_file.step.name = "Write Android LibC conf (android.conf)";
    return create_lib_c_file;
}
const InstallAndroidKeyStore = struct {
    step: *Build.Step,
    keystore_artifact: Build.LazyPath,
};
fn generateAndroidKeyStore(b: *Build.Builder) InstallAndroidKeyStore {
    const generate_key_store = b.addSystemCommand(&.{ "keytool", "-genkey", "-noprompt", "-keystore" });
    generate_key_store.setName("Generate keystore");
    const keystore_artifact = generate_key_store.addOutputFileArg(APP_NAME ++ ".keystore");
    generate_key_store.addArgs(&.{
        "-alias",
        ANDROID_KEYSTORE_ALIAS,
        "-storepass",
        ANDROID_KEYSTORE_KEYPASS,
        "-keypass",
        ANDROID_KEYSTORE_KEYPASS,
        "-dname",
        ANDROID_KEYSTORE_DNAME_STRING,
        "-keyalg",
        "RSA",
        "-keysize",
        "2048",
    });
    return .{
        .step = &generate_key_store.step,
        .keystore_artifact = keystore_artifact,
    };
}
const AndroidManifestConfig = struct {
    package: []const u8 = "",
    permissions: std.ArrayList([]const u8),
    marketing_app_name: []const u8 = APP_NAME,
    lib_name: []const u8 = "",
    has_code: bool = false,
};
fn generateAndroidManifest(
    b: *Build.Builder,
    config: AndroidManifestConfig,
) !*Build.Step.WriteFile {
    const manifest_step = b.addWriteFile("AndroidManifest.xml", blk: {
        var buf = std.ArrayList(u8).init(b.allocator);
        errdefer buf.deinit();

        var writer = buf.writer();

        @setEvalBranchQuota(1_000_000);

        try writer.print(
            \\<?xml version="1.0" encoding="utf-8" standalone="no"?>
            \\<manifest xmlns:tools="http://schemas.android.com/tools" xmlns:android="http://schemas.android.com/apk/res/android" package="{s}" android:versionCode="1">
            \\
        , .{config.package});

        for (config.permissions.items) |perm| {
            try writer.print("<uses-permission android:name=\"{s}\"/>\n", .{perm});
        }
        // TODO: we should probably use strings.xml, but whatever!
        try writer.print(
            \\<uses-sdk android:minSdkVersion="{s}" android:targetSdkVersion="{s}" />
            \\<application android:debuggable="true" android:hasCode="{s}" android:label="{s}" tools:replace="android:icon,android:theme,android:allowBackup,label" android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher_round">
            \\<activity android:configChanges="keyboardHidden|orientation" android:name="android.app.NativeActivity" android:exported="true">
            \\<meta-data android:name="android.app.lib_name" android:value="{s}"/>
            \\<intent-filter>
            \\<action android:name="android.intent.action.MAIN"/>
            \\<category android:name="android.intent.category.LAUNCHER"/>
            \\</intent-filter>
            \\</activity>
            \\</application>
            \\</manifest>
            \\
        , .{
            ANDROID_MIN_API_VERSION,
            ANDROID_TARGET_API_VERSION,
            if (config.has_code) "true" else "false",
            config.marketing_app_name,
            config.lib_name,
        });

        break :blk buf.toOwnedSlice() catch unreachable;
    });

    return manifest_step;
}

fn generateAndroidCompiledResources(
    b: *Build.Builder,
    generate_android_manifest: *Build.Step.WriteFile,
    android_sdk: *const auto_detect.AndroidSDKConfig,
) *Build.Step.Run {
    const aapt2_exe_path = b.pathJoin(&.{ android_sdk.android_sdk_root, "build-tools", ANDROID_BUILD_TOOLS_VERSION, "aapt2" });

    const compiled_resources_path = b.pathJoin(&.{ b.install_prefix, "compiled_resources" });

    const generate_resources_cmd = b.addSystemCommand(&.{ aapt2_exe_path, "compile", "--dir" });
    generate_resources_cmd.addDirectoryArg(.{ .path = b.pathJoin(&.{ "android", "res" }) });
    generate_resources_cmd.addArg("-o");
    generate_resources_cmd.addDirectoryArg(.{ .path = compiled_resources_path });

    generate_resources_cmd.step.dependOn(&generate_android_manifest.step);
    generate_resources_cmd.setName("aapt2 compile");

    const unzip_resources_cmd = b.addSystemCommand(&.{ "unzip", "-o", compiled_resources_path, "-d" });
    unzip_resources_cmd.addFileArg(.{ .path = b.fmt("{s}_unzipped", .{compiled_resources_path}) });
    unzip_resources_cmd.step.dependOn(&generate_resources_cmd.step);

    return unzip_resources_cmd;
}

fn addFilesToExec(file: Build.LazyPath, state: *anyopaque) void {
    const exec = @as(*Build.Step.Run, @alignCast(@ptrCast(state)));
    exec.addFileArg(file);
}

fn generateAndroidPreBundle(
    b: *Build.Builder,
    manifest_file_step: *Build.Step.WriteFile,
    generate_compiled_resources_step: *Build.Step.Run,
    android_sdk: *const auto_detect.AndroidSDKConfig,
    android_version: []const u8,
) *Build.Step.Run {
    const aapt2_exe_path = b.pathJoin(&.{
        android_sdk.android_sdk_root,
        "build-tools",
        ANDROID_BUILD_TOOLS_VERSION,
        "aapt2",
    });

    const generate_pre_bundle_cmd = b.addSystemCommand(&.{ aapt2_exe_path, "link", "--auto-add-overlay", "--proto-format", "-o" });
    generate_pre_bundle_cmd.addFileArg(.{ .path = b.pathJoin(&.{ b.install_prefix, "output.apk" }) });
    generate_pre_bundle_cmd.addArg("-I");
    generate_pre_bundle_cmd.addFileArg(.{
        .path = b.pathJoin(&.{
            android_sdk.android_sdk_root,
            "platforms",
            b.fmt("android-{s}", .{android_version}),
            "android.jar",
        }),
    });
    generate_pre_bundle_cmd.addArg("--manifest");
    generate_pre_bundle_cmd.addFileArg(manifest_file_step.files.getLast().getPath());
    generate_pre_bundle_cmd.addArg("-R");

    const compiled_resources_path = b.pathJoin(&.{ b.install_prefix, "compiled_resources_unzipped" });
    const get_flat_files_step = ListFiles.create(
        b,
        .{ .path = compiled_resources_path },
        addFilesToExec,
        @ptrCast(generate_pre_bundle_cmd),
    );
    get_flat_files_step.step.dependOn(&generate_compiled_resources_step.step);
    generate_pre_bundle_cmd.step.dependOn(&get_flat_files_step.step);
    generate_pre_bundle_cmd.setName("aapt2 link");

    // this looks stupid (and it is) but its actually a legit step in building the android app (*facepalm*)
    // also its going to get more stupid so get ready for that.
    // https://developer.android.com/build/building-cmdline
    const unzip_cmd = b.addSystemCommand(&.{
        "unzip", "-o", b.pathJoin(&.{ b.install_prefix, "output.apk" }), "-d", b.pathJoin(&.{ b.install_prefix, "output_unzipped" }),
    });
    unzip_cmd.step.dependOn(&generate_pre_bundle_cmd.step);

    return unzip_cmd;
}

const AndroidAppSecondBundle = struct {
    step: *Build.Step,
    second_bundle_artifact: Build.LazyPath,
};
fn generateAndroidAppSecondPreBundle(b: *Build.Builder, generate_pre_bundle_step: *Build.Step.Run, combo_lib: *Build.Step.InstallArtifact) AndroidAppSecondBundle {
    const wf = b.addWriteFiles();
    wf.step.dependOn(&generate_pre_bundle_step.step);

    const prebundle_path = b.pathJoin(&.{ b.install_prefix, "output_unzipped" });

    _ = wf.addCopyFile(.{ .path = b.pathJoin(&.{ prebundle_path, "AndroidManifest.xml" }) }, "manifest/AndroidManifest.xml");

    _ = wf.addCopyFile(.{ .path = b.pathJoin(&.{ prebundle_path, "resources.pb" }) }, "resources.pb");

    const lib_location = combo_lib.artifact.getEmittedBin();
    const lib_name = combo_lib.artifact.out_lib_filename;
    const target = combo_lib.artifact.target;

    const lib_dir_name = switch (target.cpu_arch.?) {
        .aarch64 => "arm64-v8a",
        .x86_64 => "x86_64",
        else => @panic("unsupported arch for android build"),
    };

    _ = wf.addCopyFile(
        lib_location,
        b.pathJoin(&.{ "lib", lib_dir_name, lib_name }),
    );

    const copyRes = b.addSystemCommand(&.{ "cp", "-R", b.pathJoin(&.{ prebundle_path, "res" }) });
    copyRes.addDirectoryArg(wf.getDirectory());
    copyRes.setName("Copy output_unzipped/res into bundle folder");
    copyRes.step.dependOn(&wf.step);

    var zip_files = b.addSystemCommand(&.{ "zip", "-D4r" });
    var output_zip = zip_files.addOutputFileArg("output_part2.zip");
    zip_files.addArg(".");
    zip_files.step.dependOn(&copyRes.step);
    zip_files.step.dependOn(&wf.step);
    zip_files.setCwd(wf.getDirectory());

    return .{
        .step = &zip_files.step,
        .second_bundle_artifact = output_zip,
    };
}
const InstallAndroidAppBundle = struct {
    step: *Build.Step,
    aab_artifact: Build.LazyPath,
};
fn generateAndroidAppBundle(b: *Build.Builder, android_app_second_bundle: AndroidAppSecondBundle) InstallAndroidAppBundle {
    // imagine not having a core part of your sdk's build system not included in your sdk installation
    // oh wait you dont have to imagine! the geniuses at Google already did that!
    const bundle_tool_exe_path = "bundletool";

    const generate_app_bundle_cmd = b.addSystemCommand(&.{ bundle_tool_exe_path, "build-bundle", "--modules" });
    generate_app_bundle_cmd.step.dependOn(android_app_second_bundle.step);
    generate_app_bundle_cmd.addFileArg(android_app_second_bundle.second_bundle_artifact);
    generate_app_bundle_cmd.addArg("--output");
    var output_aab = generate_app_bundle_cmd.addOutputFileArg(APP_NAME ++ ".aab");

    return .{ .step = &generate_app_bundle_cmd.step, .aab_artifact = output_aab };
}
fn generateAndroidApks(b: *Build.Builder, install_keystore: InstallAndroidKeyStore, install_android_app_bundle: InstallAndroidAppBundle) *Build.Step.InstallFile {
    const bundle_tool_exe_path = "bundletool";

    const generate_app_bundle_cmd = b.addSystemCommand(&.{ bundle_tool_exe_path, "build-apks", "--overwrite", "--ks" });
    generate_app_bundle_cmd.step.dependOn(install_keystore.step);
    generate_app_bundle_cmd.addFileArg(install_keystore.keystore_artifact);
    generate_app_bundle_cmd.addArgs(&.{
        "--ks-key-alias",
        ANDROID_KEYSTORE_ALIAS,
        "--key-pass",
        "pass:" ++ ANDROID_KEYSTORE_KEYPASS,
        "--ks-pass",
        "pass:" ++ ANDROID_KEYSTORE_KEYPASS,
        "--bundle",
    });
    generate_app_bundle_cmd.step.dependOn(install_android_app_bundle.step);
    generate_app_bundle_cmd.addFileArg(install_android_app_bundle.aab_artifact);
    generate_app_bundle_cmd.addArg("--output");
    var output_apks = generate_app_bundle_cmd.addOutputFileArg(APP_NAME ++ ".apks");
    const install_apks = b.addInstallFile(output_apks, APP_NAME ++ ".apks");
    install_apks.step.dependOn(&generate_app_bundle_cmd.step);
    return install_apks;
}
