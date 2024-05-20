const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");
const auto_detect = @import("build/auto-detect.zig");
const ListFiles = @import("build/ListFiles.zig");
const FetchFile = @import("build/FetchFile.zig");
const CreateAndroidAppBundle = @import("build/CreateAndroidAppBundle.zig");
const InstallAndroidKeyStore = CreateAndroidAppBundle.InstallAndroidKeyStore;

const APP_NAME = "MyApp";
const BUNDLE_PREFIX = "com.example";

const BUNDLETOOL_JAR_URL = "https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar";

const ANDROID_TARGET_API_VERSION = "32";
const ANDROID_MIN_API_VERSION = "32";
const ANDROID_BUILD_TOOLS_VERSION = "34.0.0";
const ANDROID_NDK_VERSION = "26.1.10909125";

const ANDROID_KEYSTORE_ALIAS = "androidkey";
const ANDROID_KEYSTORE_DNAME_STRING = "CN=Unknown, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=Unknown";
const ANDROID_KEYSTORE_KEYPASS = "android";

pub fn build(b: *Build) !void {
    // targets
    const default_target = b.standardTargetOptions(.{});
    const native_target = b.resolveTargetQuery(try std.zig.CrossTarget.parse(.{ .arch_os_abi = "native" }));
    const ios_target = b.resolveTargetQuery(try std.zig.CrossTarget.parse(.{ .arch_os_abi = "aarch64-ios" }));
    const ios_sim_target = b.resolveTargetQuery(try std.zig.CrossTarget.parse(.{
        .arch_os_abi = if (native_target.result.cpu.arch.isAARCH64()) "aarch64-ios-simulator" else "x86_64-ios-simulator",
    }));
    const android_arm64_target = b.resolveTargetQuery(try std.zig.CrossTarget.parse(.{
        .arch_os_abi = "aarch64-linux-android",
        .cpu_features = "baseline+v8a",
    }));
    const optimize = b.standardOptimizeOption(.{});

    const android_sdk = try auto_detect.findAndroidSDKConfig(b, &android_arm64_target.result, .{
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
    const ios_build_lib = try buildAppStaticLib(b, ios_target, optimize);
    const ios_sim_build_lib = try buildAppStaticLib(b, ios_sim_target, optimize);

    const android_combo_lib = try buildAppSharedLib(
        b,
        android_arm64_target,
        optimize,
    );

    android_combo_lib.step.dependOn(&generate_libc_file.step);
    android_combo_lib.artifact.setLibCFile(generate_libc_file.files.getLast().getPath());

    // generate iOS framework files
    const ios_build_lib_name = "ios_lib" ++ APP_NAME ++ ".xcframework";

    const generate_ios_app_framework = b.addSystemCommand(&.{
        "xcodebuild",
        "-create-xcframework",
        "-library",
    });
    generate_ios_app_framework.addFileArg(ios_build_lib.artifact.getEmittedBin());
    generate_ios_app_framework.addArg("-library");
    generate_ios_app_framework.addFileArg(ios_sim_build_lib.artifact.getEmittedBin());
    generate_ios_app_framework.addArg("-output");
    const ios_app_framework = generate_ios_app_framework.addOutputFileArg(ios_build_lib_name);
    generate_ios_app_framework.step.dependOn(&ios_build_lib.step);
    generate_ios_app_framework.step.dependOn(&ios_sim_build_lib.step);

    // create folder structure for xcode project
    const xcode_proj = b.addWriteFiles();
    const project_yml_loc = xcode_proj.addCopyFile(.{ .path = b.pathJoin(&.{ "ios", "project.yml" }) }, "project.yml");

    const copy_app_ios_sources = b.addSystemCommand(&.{ "cp", "-r" });
    copy_app_ios_sources.addDirectoryArg(.{ .path = b.pathJoin(&.{ "ios", "src" }) });
    copy_app_ios_sources.addDirectoryArg(xcode_proj.getDirectory());
    copy_app_ios_sources.step.dependOn(&xcode_proj.step);

    const copy_app_framework = b.addSystemCommand(&.{ "cp", "-r" });
    copy_app_framework.addDirectoryArg(ios_app_framework);
    copy_app_framework.addDirectoryArg(xcode_proj.getDirectory());
    copy_app_framework.step.dependOn(&xcode_proj.step);

    // generate xcode project
    const generate_xcode_proj = b.addSystemCommand(&.{ "xcodegen", "generate", "--spec" });
    generate_xcode_proj.addFileArg(project_yml_loc);
    generate_xcode_proj.setEnvironmentVariable("APP_LIB", ios_build_lib_name);
    generate_xcode_proj.setEnvironmentVariable("APP_NAME", APP_NAME);
    generate_xcode_proj.setEnvironmentVariable("BUNDLE_PREFIX", BUNDLE_PREFIX);
    generate_xcode_proj.setCwd(xcode_proj.getDirectory());
    generate_xcode_proj.expectExitCode(0);
    generate_xcode_proj.step.dependOn(&generate_ios_app_framework.step);
    generate_xcode_proj.step.dependOn(&copy_app_ios_sources.step);
    generate_xcode_proj.step.dependOn(&copy_app_framework.step);

    const output_xcode_project = b.addInstallDirectory(.{
        .source_dir = xcode_proj.getDirectory(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "ios",
    });
    output_xcode_project.step.dependOn(&generate_xcode_proj.step);

    // !! can't build since no team specified in xcode project !!

    // // build iOS app with xcodebuild and the generated xcode project
    // const xcodebuild = b.addSystemCommand(
    //     &.{ "xcodebuild", "-project", b.pathJoin(&.{ b.install_prefix, APP_NAME ++ ".xcodeproj" }), "-target", APP_NAME },
    // );
    // xcodebuild.step.dependOn(&generate_xcode_proj.step);
    // xcodebuild.step.dependOn(&generate_ios_app_framework.step);
    // xcodebuild.step.dependOn(&generate_ios_sokol_framework.step);

    // android
    const bundletool_install_folder = b.addWriteFiles();
    const bundletool_install_loc = bundletool_install_folder.add("bundletool.jar", "");
    const fetch_bundletool = FetchFile.create(b, BUNDLETOOL_JAR_URL, bundletool_install_loc);
    fetch_bundletool.step.name = "Fetch bundletool";

    const install_keystore = generateAndroidKeyStore(b, android_sdk.keytool_path);

    var permissions = std.ArrayList([]const u8).init(b.allocator);
    defer permissions.deinit();
    try permissions.append("android.permission.SET_RELEASE_APP");
    try permissions.append("android.permission.INTERNET");
    try permissions.append("android.permission.ACCESS_NETWORK_STATE");
    const generate_android_manifest = try generateAndroidManifest(
        b,
        .{ .package = BUNDLE_PREFIX ++ "." ++ APP_NAME, .lib_name = android_combo_lib.artifact.name, .permissions = permissions },
    );
    generate_android_manifest.step.dependOn(&android_combo_lib.step);

    const create_android_app_bundle = CreateAndroidAppBundle.create(
        b,
        APP_NAME,
        install_keystore,
        android_combo_lib,
        generate_android_manifest,
        android_sdk,
        fetch_bundletool,
    );

    // native build exe
    const default_exe = try buildExe(b, default_target, optimize);
    const install_default_exe = b.addInstallArtifact(default_exe, .{});

    // entrypoint build steps
    const install_ios = b.step("ios", "Setup iOS project");
    install_ios.dependOn(&output_xcode_project.step);

    const install_default = b.step("default", "Build binaries for the current system (or specified in command)");
    install_default.dependOn(&install_default_exe.step);

    const install_android = b.step("android", "Build android project");
    install_android.dependOn(&create_android_app_bundle.step);

    const run_exe = b.addRunArtifact(default_exe);
    const run_step = b.step("run", "Run project");
    run_step.dependOn(&run_exe.step);

    const all_step = b.step("all", "Build everything");
    all_step.dependOn(install_default);
    all_step.dependOn(install_ios);
    all_step.dependOn(install_android);

    b.default_step = all_step;
}

fn getEntrypointFile(target: Build.ResolvedTarget) ![]const u8 {
    var entrypoint: []const u8 = "main.zig";

    if (target.result.isAndroid()) {
        entrypoint = "main.android.zig";
    }
    return entrypoint;
}

fn buildExe(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*Build.Step.Compile {
    const triple = try target.result.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});

    const entrypoint = try getEntrypointFile(target);

    const exe = b.addExecutable(.{
        .name = name,
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = entrypoint },
    });

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol_module = dep_sokol.module("sokol");
    const items = sokol_module.link_objects.items;
    for (items) |sokol_lib| {
        switch (sokol_lib) {
            .other_step => |sokol_compile_lib| try addCompilePaths(b, target, sokol_compile_lib),
            else => {},
        }
    }
    exe.root_module.addImport("sokol", dep_sokol.module("sokol"));
    try addCompilePaths(b, target, exe);

    return exe;
}

fn buildAppStaticLib(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*Build.Step.InstallArtifact {
    const triple = try target.result.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});

    const entrypoint = try getEntrypointFile(target);

    const lib = b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
        .root_source_file = .{
            .path = entrypoint,
        },
    });

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol_module = dep_sokol.module("sokol");
    const items = sokol_module.link_objects.items;
    for (items) |sokol_lib| {
        switch (sokol_lib) {
            .other_step => |sokol_compile_lib| try addCompilePaths(b, target, sokol_compile_lib),
            else => {},
        }
    }
    lib.root_module.addImport("sokol", sokol_module);
    try addCompilePaths(b, target, lib);

    const install_lib = b.addInstallArtifact(lib, .{});

    return install_lib;
}

fn buildAppSharedLib(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*Build.Step.InstallArtifact {
    const triple = try target.result.zigTriple(b.allocator);
    const name = b.fmt(APP_NAME ++ "_{s}", .{triple});

    const entrypoint = try getEntrypointFile(target);

    const lib = b.addSharedLibrary(.{ .name = name, .target = target, .optimize = optimize, .root_source_file = .{ .path = entrypoint } });
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const sokol_module = dep_sokol.module("sokol");
    const items = sokol_module.link_objects.items;
    for (items) |sokol_lib| {
        switch (sokol_lib) {
            .other_step => |sokol_compile_lib| try addCompilePaths(b, target, sokol_compile_lib),
            else => {},
        }
    }
    lib.root_module.addImport("sokol", sokol_module);
    try addCompilePaths(b, target, lib);

    const install_lib = b.addInstallArtifact(lib, .{});
    return install_lib;
}

fn addCompilePaths(b: *Build, target: Build.ResolvedTarget, step: anytype) !void {
    if (target.result.os.tag == .ios) {
        const sysroot = std.zig.system.darwin.getSdk(b.allocator, target.result) orelse b.sysroot;
        step.addLibraryPath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/usr/lib" }) }); //(.{ .cwd_relative = "/usr/lib" });
        step.addIncludePath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/usr/include" }) }); //(.{ .cwd_relative = "/usr/include" });
        step.addFrameworkPath(.{ .path = b.pathJoin(&.{ sysroot orelse "", "/System/Library/Frameworks" }) }); //(.{ .cwd_relative = "/System/Library/Frameworks" });
    } else if (target.result.isAndroid()) {
        const target_dir_name = switch (target.result.cpu.arch) {
            .aarch64 => "aarch64-linux-android",
            .x86_64 => "x86_64-linux-android",
            else => @panic("unsupported arch for android build"),
        };
        _ = target_dir_name;

        const android_sdk = try auto_detect.findAndroidSDKConfig(b, &target.result, .{
            .api_version = ANDROID_TARGET_API_VERSION,
            .build_tools_version = ANDROID_BUILD_TOOLS_VERSION,
            .ndk_version = ANDROID_NDK_VERSION,
        });

        step.addIncludePath(.{ .path = android_sdk.android_ndk_include });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_android });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_host });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_host_android });
        step.addIncludePath(.{ .path = android_sdk.android_ndk_include_host_arch_android });

        //step.linkLibC();

        step.addLibraryPath(.{ .path = android_sdk.android_ndk_lib_host_arch_android });
    }
}

// Based off of https://github.com/MasterQ32/ZigAndroidTemplate/blob/master/Sdk.zig#L906
const LibCFileConfig = struct {
    include_dir: []const u8 = "",
    sys_include_dir: []const u8 = "",
    crt_dir: []const u8 = "",
};
fn createLibCFile(b: *Build, config: LibCFileConfig) !*Build.Step.WriteFile {
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

fn generateAndroidKeyStore(b: *Build, keytool_exe: []const u8) InstallAndroidKeyStore {
    const generate_key_store = b.addSystemCommand(&.{ keytool_exe, "-genkey", "-noprompt", "-keystore" });
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
        .alias = ANDROID_KEYSTORE_ALIAS,
        .keypass = ANDROID_KEYSTORE_KEYPASS,
        .dname = ANDROID_KEYSTORE_DNAME_STRING,
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
    b: *Build,
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

const RunStepAndOutputDir = struct {
    run_step: *Build.Step.Run,
    output_directory: Build.LazyPath,
};
fn generateAndroidCompiledResources(
    b: *Build,
    generate_android_manifest: *Build.Step.WriteFile,
    android_sdk: *const auto_detect.AndroidSDKConfig,
) RunStepAndOutputDir {
    const aapt2_exe_path = b.pathJoin(&.{ android_sdk.android_sdk_root, "build-tools", ANDROID_BUILD_TOOLS_VERSION, "aapt2" });

    const generate_resources_cmd = b.addSystemCommand(&.{ aapt2_exe_path, "compile", "--dir" });
    generate_resources_cmd.addDirectoryArg(.{ .path = b.pathJoin(&.{ "android", "res" }) });
    generate_resources_cmd.addArg("-o");
    const compiled_resources_dir = generate_resources_cmd.addOutputFileArg("compiled_resources/");

    generate_resources_cmd.step.dependOn(&generate_android_manifest.step);
    generate_resources_cmd.setName("aapt2 compile");

    return .{
        .run_step = generate_resources_cmd,
        .output_directory = compiled_resources_dir,
    };
}

fn addFilesToExec(file: Build.LazyPath, state: *anyopaque) void {
    const exec = @as(*Build.Step.Run, @alignCast(@ptrCast(state)));
    exec.addFileArg(file);
}

fn generateAndroidPreBundle(
    b: *Build,
    manifest_file_step: *Build.Step.WriteFile,
    create_compiled_resources: RunStepAndOutputDir,
    android_sdk: *const auto_detect.AndroidSDKConfig,
    android_version: []const u8,
) RunStepAndOutputDir {
    const aapt2_exe_path = b.pathJoin(&.{
        android_sdk.android_sdk_root,
        "build-tools",
        ANDROID_BUILD_TOOLS_VERSION,
        "aapt2",
    });
    const compiled_resources_path = create_compiled_resources.output_directory;

    const generate_pre_bundle_cmd = b.addSystemCommand(&.{
        aapt2_exe_path,
        "link",
        "--auto-add-overlay",
        "--proto-format",
        "--output-to-dir",
        "-o",
    });
    const output_apk_path = generate_pre_bundle_cmd.addOutputFileArg("output/");
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

    const get_flat_files_step = ListFiles.create(
        b,
        compiled_resources_path,
        addFilesToExec,
        @ptrCast(generate_pre_bundle_cmd),
    );
    get_flat_files_step.step.dependOn(&create_compiled_resources.run_step.step);
    generate_pre_bundle_cmd.step.dependOn(&get_flat_files_step.step);
    generate_pre_bundle_cmd.setName("aapt2 link");

    return .{
        .run_step = generate_pre_bundle_cmd,
        .output_directory = output_apk_path,
    };
}

fn generateAndroidAppSecondPreBundle(
    b: *Build,
    generate_pre_bundle_step: RunStepAndOutputDir,
    combo_lib: *Build.Step.InstallArtifact,
) RunStepAndOutputDir {
    const wf = b.addWriteFiles();
    wf.step.dependOn(&generate_pre_bundle_step.run_step.step);

    const prebundle_path = generate_pre_bundle_step.output_directory;

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
    const output_zip = zip_files.addOutputFileArg("output_part2.zip");
    zip_files.addArg(".");
    zip_files.step.dependOn(&copyRes.step);
    zip_files.step.dependOn(&wf.step);
    zip_files.setCwd(wf.getDirectory());

    return .{
        .run_step = zip_files,
        .output_directory = output_zip,
    };
}

fn generateAndroidAppBundle(
    b: *Build,
    java_path: []const u8,
    bundletool_install_step: *FetchFile,
    android_app_second_bundle: RunStepAndOutputDir,
) RunStepAndOutputDir {
    const generate_app_bundle_cmd = b.addSystemCommand(&.{ java_path, "-jar" });
    generate_app_bundle_cmd.addFileArg(bundletool_install_step.destination);
    generate_app_bundle_cmd.addArgs(&.{ "build-bundle", "--modules" });
    generate_app_bundle_cmd.step.dependOn(&android_app_second_bundle.run_step.step);
    generate_app_bundle_cmd.step.dependOn(&bundletool_install_step.step);
    generate_app_bundle_cmd.addFileArg(android_app_second_bundle.output_directory);
    generate_app_bundle_cmd.addArg("--output");
    const output_aab = generate_app_bundle_cmd.addOutputFileArg(APP_NAME ++ ".aab");

    return .{
        .run_step = generate_app_bundle_cmd,
        .output_directory = output_aab,
    };
}

fn generateAndroidApks(
    b: *Build,
    java_path: []const u8,
    bundletool_install_step: *FetchFile,
    install_keystore: InstallAndroidKeyStore,
    install_android_app_bundle: RunStepAndOutputDir,
) *Build.Step.InstallFile {
    const generate_app_bundle_cmd = b.addSystemCommand(&.{ java_path, "-jar" });
    generate_app_bundle_cmd.addFileArg(bundletool_install_step.destination);
    generate_app_bundle_cmd.addArgs(&.{ "build-apks", "--overwrite", "--ks" });
    generate_app_bundle_cmd.step.dependOn(install_keystore.step);
    generate_app_bundle_cmd.step.dependOn(&bundletool_install_step.step);
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
    generate_app_bundle_cmd.step.dependOn(&install_android_app_bundle.run_step.step);
    generate_app_bundle_cmd.addFileArg(install_android_app_bundle.output_directory);
    generate_app_bundle_cmd.addArg("--output");
    const output_apks = generate_app_bundle_cmd.addOutputFileArg(APP_NAME ++ ".apks");
    const install_apks = b.addInstallFile(output_apks, APP_NAME ++ ".apks");
    install_apks.step.dependOn(&generate_app_bundle_cmd.step);
    return install_apks;
}
