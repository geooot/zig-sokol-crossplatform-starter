// Taken and Modified from https://github.com/MasterQ32/ZigAndroidTemplate/blob/master/build/auto-detect.zig
// Copyright (c) 2020 Felix "xq" Queißner
// This file is under the MIT License

const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

const print = std.debug.print;

pub const ToolchainVersions = struct {
    api_version: []const u8 = "34",
    build_tools_version: []const u8 = "34.0.0",
    ndk_version: []const u8 = "26.1.10909125",
};

pub const AndroidSDKConfig = struct {
    valid_config: bool = true,

    android_sdk_root: []const u8 = "",
    android_ndk_root: []const u8 = "",
    java_home: []const u8 = "",

    keytool_path: []const u8 = "",

    android_ndk_include: []const u8 = "",
    android_ndk_include_android: []const u8 = "",
    android_ndk_include_host: []const u8 = "",
    android_ndk_include_host_android: []const u8 = "",
    android_ndk_include_host_arch_android: []const u8 = "",
    android_ndk_lib_host_arch_android: []const u8 = "",
};

var config: AndroidSDKConfig = .{};

pub fn findAndroidSDKConfig(b: *Builder, target: *const std.zig.CrossTarget, versions: ToolchainVersions) !AndroidSDKConfig {
    if (config.android_sdk_root.len == 0) {
        // try to find the android home
        const android_home_val = std.process.getEnvVarOwned(b.allocator, "ANDROID_HOME") catch "";
        if (android_home_val.len > 0) {
            if (findProblemWithAndroidSdk(b, versions, android_home_val)) |problem| {
                print("Cannot use ANDROID_HOME ({s}):\n    {s}\n", .{ android_home_val, problem });
            } else {
                print("Using android sdk at ANDROID_HOME: {s}\n", .{android_home_val});
                config.android_sdk_root = android_home_val;
            }
        }
    }

    if (config.android_sdk_root.len == 0) {
        // try to find the android home
        const android_sdk_root = std.process.getEnvVarOwned(b.allocator, "ANDROID_SDK_ROOT") catch "";
        if (android_sdk_root.len > 0) {
            if (findProblemWithAndroidSdk(b, versions, android_sdk_root)) |problem| {
                print("Cannot use ANDROID_SDK_ROOT ({s}):\n    {s}\n", .{ android_sdk_root, problem });
            } else {
                print("Using android sdk at ANDROID_SDK_ROOT: {s}\n", .{android_sdk_root});
                config.android_sdk_root = android_sdk_root;
            }
        }
    }

    // if we still don't have an sdk, see if `adb` is on the path and try to use that.
    if (config.android_sdk_root.len == 0) {
        if (findProgramPath(b.allocator, "adb")) |path| {
            const sep = std.fs.path.sep;
            if (std.mem.lastIndexOfScalar(u8, path, sep)) |index| {
                var rest = path[0..index];
                const parent = "platform-tools";
                if (std.mem.endsWith(u8, rest, parent) and rest[rest.len - parent.len - 1] == sep) {
                    const sdk_path = rest[0 .. rest.len - parent.len - 1];
                    if (findProblemWithAndroidSdk(b, versions, sdk_path)) |problem| {
                        print("Cannot use SDK near adb\n    at {s}:\n    {s}\n", .{ sdk_path, problem });
                    } else {
                        print("Using android sdk near adb: {s}\n", .{sdk_path});
                        config.android_sdk_root = sdk_path;
                    }
                }
            }
        }
    }

    // Next up, NDK.
    // first, check ANDROID_NDK_ROOT
    if (config.android_ndk_root.len == 0) {
        const ndk_root_val = std.process.getEnvVarOwned(b.allocator, "ANDROID_NDK_ROOT") catch "";
        if (ndk_root_val.len > 0) {
            if (findProblemWithAndroidNdk(b, versions, ndk_root_val)) |problem| {
                print("Cannot use ANDROID_NDK_ROOT ({s}):\n    {s}\n", .{ ndk_root_val, problem });
            } else {
                print("Using android ndk at ANDROID_NDK_ROOT: {s}\n", .{ndk_root_val});
                config.android_ndk_root = ndk_root_val;
            }
        }
    }

    // Then check for a side-by-side install
    if (config.android_ndk_root.len == 0) {
        if (config.android_sdk_root.len > 0) {
            const ndk_root = std.fs.path.join(b.allocator, &[_][]const u8{
                config.android_sdk_root,
                "ndk",
                versions.ndk_version,
            }) catch unreachable;
            if (findProblemWithAndroidNdk(b, versions, ndk_root)) |problem| {
                print("Cannot use side by side NDK ({s}):\n    {s}\n", .{ ndk_root, problem });
            } else {
                print("Using side by side NDK install: {s}\n", .{ndk_root});
                config.android_ndk_root = ndk_root;
            }
        }
    }

    // Finally, we need to find the JDK, for keytool.
    // Check the JAVA_HOME variable
    if (config.java_home.len == 0) {
        const java_home_value = std.process.getEnvVarOwned(b.allocator, "JAVA_HOME") catch "";
        if (java_home_value.len > 0) {
            if (findProblemWithJdk(b, java_home_value)) |problem| {
                print("Cannot use JAVA_HOME ({s}):\n    {s}\n", .{ java_home_value, problem });
            } else {
                print("Using java JAVA_HOME: {s}\n", .{java_home_value});
                config.java_home = java_home_value;
            }
        }
    }

    // Look for `where keytool`
    if (config.java_home.len == 0) {
        if (findProgramPath(b.allocator, "keytool")) |path| {
            const sep = std.fs.path.sep;
            if (std.mem.lastIndexOfScalar(u8, path, sep)) |last_slash| {
                if (std.mem.lastIndexOfScalar(u8, path[0..last_slash], sep)) |second_slash| {
                    const home = path[0..second_slash];
                    if (findProblemWithJdk(b, home)) |problem| {
                        print("Cannot use java at ({s}):\n    {s}\n", .{ home, problem });
                    } else {
                        print("Using java at {s}\n", .{home});
                        config.java_home = home;
                    }
                }
            }
        }
    }

    // Check if the config is invalid.
    if (config.android_sdk_root.len == 0 or
        config.android_ndk_root.len == 0 or
        config.java_home.len == 0)
    {
        config.valid_config = false;
        if (config.android_sdk_root.len == 0) {
            print("Android SDK root is missing. Edit the config file, or set ANDROID_SDK_ROOT to your android install.\n", .{});
            print("You will need build tools version {s} and android sdk platform {s}\n\n", .{ versions.build_tools_version, "TODO: ???" });
        }
        if (config.android_ndk_root.len == 0) {
            print("Android NDK root is missing. Edit the config file, or set ANDROID_NDK_ROOT to your android NDK install.\n", .{});
            print("You will need NDK version {s}\n\n", .{versions.ndk_version});
        }
        if (config.java_home.len == 0) {
            print("Java JDK is missing. Edit the config file, or set JAVA_HOME to your JDK install.\n", .{});
            if (builtin.os.tag == .windows) {
                print("Installing Android Studio will also install a suitable JDK.\n", .{});
            }
            print("\n", .{});
        }
    }

    const target_dir_name = switch (target.cpu_arch.?) {
        .aarch64 => "aarch64-linux-android",
        .x86_64 => "x86_64-linux-android",
        else => @panic("unsupported arch for android build"),
    };
    const keytool_path = b.pathJoin(&.{ config.java_home, "bin", "keytool" ++ if (builtin.os.tag == .windows) ".exe" else "" });
    const ndk_root = config.android_ndk_root;
    const ndk_include = b.pathJoin(&.{ ndk_root, "/sysroot/usr/include" });
    const ndk_include_android = b.pathJoin(&.{ ndk_include, "android" });
    const ndk_sysroot = b.pathJoin(&.{ ndk_root, "/toolchains/llvm/prebuilt", toolchainHostTag(), "/sysroot" });
    const ndk_include_host = b.pathJoin(&.{ ndk_sysroot, "/usr/include" });
    const ndk_include_host_android = b.pathJoin(&.{ ndk_include_host, "android" });
    const ndk_include_host_arch_android = b.pathJoin(&.{ ndk_include_host, target_dir_name });
    const ndk_lib_host_arch_android = b.pathJoin(&.{ ndk_sysroot, "/usr/lib", target_dir_name, versions.api_version });

    config.keytool_path = keytool_path;
    config.android_ndk_root = ndk_root;
    config.android_ndk_include = ndk_include;
    config.android_ndk_include_android = ndk_include_android;
    config.android_ndk_include_host = ndk_include_host;
    config.android_ndk_include_host_android = ndk_include_host_android;
    config.android_ndk_include_host_arch_android = ndk_include_host_arch_android;
    config.android_ndk_lib_host_arch_android = ndk_lib_host_arch_android;

    return config;
}

pub fn findProgramPath(allocator: std.mem.Allocator, program: []const u8) ?[]const u8 {
    const args: []const []const u8 = if (builtin.os.tag == .windows)
        &[_][]const u8{ "where", program }
    else
        &[_][]const u8{ "which", program };

    var proc = std.ChildProcess.init(args, allocator);

    proc.stderr_behavior = .Close;
    proc.stdout_behavior = .Pipe;
    proc.stdin_behavior = .Close;

    proc.spawn() catch return null;

    const stdout = proc.stdout.?.readToEndAlloc(allocator, 1024) catch return null;
    const term = proc.wait() catch return null;
    switch (term) {
        .Exited => |rc| {
            if (rc != 0) return null;
        },
        else => return null,
    }

    var path = std.mem.trim(u8, stdout, " \t\r\n");
    if (std.mem.indexOfScalar(u8, path, '\n')) |index| {
        path = std.mem.trim(u8, path[0..index], " \t\r\n");
    }
    if (path.len > 0) return path;

    return null;
}

// Returns the problem with an android_home path.
// If it seems alright, returns null.
fn findProblemWithAndroidSdk(b: *Builder, versions: ToolchainVersions, path: []const u8) ?[]const u8 {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return "Directory does not exist";
        return b.fmt("Cannot access {s}, {s}", .{ path, @errorName(err) });
    };

    const build_tools = pathConcat(b, path, "build-tools");
    std.fs.cwd().access(build_tools, .{}) catch |err| {
        return b.fmt("Cannot access build-tools/, {s}", .{@errorName(err)});
    };

    const versioned_tools = pathConcat(b, build_tools, versions.build_tools_version);
    std.fs.cwd().access(versioned_tools, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return b.fmt("Missing build tools version {s}", .{versions.build_tools_version});
        } else {
            return b.fmt("Cannot access build-tools/{s}/, {s}", .{ versions.build_tools_version, @errorName(err) });
        }
    };

    // var str_buf: [5]u8 = undefined;
    // const android_version_str = "TODO: ???"; // versions.androidSdkString(&str_buf);

    // const platforms = pathConcat(b, path, "platforms");
    // const platform_version = pathConcat(b, platforms, b.fmt("android-{d}", .{versions.android_sdk_version}));
    // std.fs.cwd().access(platform_version, .{}) catch |err| {
    //     if (err == error.FileNotFound) {
    //         return b.fmt("Missing android platform version {s}", .{android_version_str});
    //     } else {
    //         return b.fmt("Cannot access platforms/android-{s}, {s}", .{ android_version_str, @errorName(err) });
    //     }
    // };

    return null;
}

// linux-x86_64
pub fn toolchainHostTag() []const u8 {
    const os = builtin.target.os.tag;
    return (if (os == .macos) "darwin" else @tagName(os)) ++ "-x86_64"; // HACK: Android SDK always seems to put it under x86_64 even in aarch64 envs
}

// Returns the problem with an android ndk path.
// If it seems alright, returns null.
fn findProblemWithAndroidNdk(b: *Builder, versions: ToolchainVersions, path: []const u8) ?[]const u8 {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return "Directory does not exist";
        return b.fmt("Cannot access {s}, {s}", .{ path, @errorName(err) });
    };

    const ndk_include_path = std.fs.path.join(b.allocator, &[_][]const u8{
        path,
        "toolchains",
        "llvm",
        "prebuilt",
        toolchainHostTag(),
        "sysroot",
        "usr",
        "include",
    }) catch unreachable;
    std.fs.cwd().access(ndk_include_path, .{}) catch |err| {
        return b.fmt("Cannot access {s}, {s}\nMake sure you are using NDK {s}.", .{ ndk_include_path, @errorName(err), versions.ndk_version });
    };

    return null;
}

// Returns the problem with a jdk install.
// If it seems alright, returns null.
fn findProblemWithJdk(b: *Builder, path: []const u8) ?[]const u8 {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return "Directory does not exist";
        return b.fmt("Cannot access {s}, {s}", .{ path, @errorName(err) });
    };

    const target_path = b.pathJoin(&.{ path, "bin", "keytool" ++ if (builtin.os.tag == .windows) ".exe" else "" });
    std.fs.cwd().access(target_path, .{}) catch |err| {
        return b.fmt("Cannot access keytool, {s}", .{@errorName(err)});
    };

    return null;
}

fn pathConcat(b: *Builder, left: []const u8, right: []const u8) []const u8 {
    return std.fs.path.join(b.allocator, &[_][]const u8{ left, right }) catch unreachable;
}

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return false;
        std.log.debug("Cannot access {s}, {s}", .{ path, @errorName(err) });
        return false;
    };
    return true;
}
