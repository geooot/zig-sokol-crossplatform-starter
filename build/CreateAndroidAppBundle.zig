const CreateAndroidAppBundle = @This();
const std = @import("std");
const fs = std.fs;
const auto_detect = @import("./auto-detect.zig");
const FetchFile = @import("./FetchFile.zig");
const Step = std.Build.Step;

pub const InstallAndroidKeyStore = struct {
    step: *std.Build.Step,
    keystore_artifact: std.Build.LazyPath,
    alias: []const u8,
    keypass: []const u8,
    dname: []const u8,
};

generate_compiled_resource_step: Step,
list_files_from_compiled_resources_step: Step,
generate_pre_bundle_step: Step,
copy_into_second_pre_bundle_step: Step,
generate_second_pre_bundle_step: Step,
generate_app_bundle_step: Step,
generate_apks_step: Step,
step: Step,

combo_lib: *std.Build.Step.InstallArtifact,
manifest_wf: *std.Build.Step.WriteFile,

compiled_resources_dir: ?std.Build.LazyPath,
generate_pre_bundle_cmd: ?*std.Build.Step.Run,
link_output_dir: ?std.Build.LazyPath,
second_pre_bundle_input_folder: ?*std.Build.Step.WriteFile,

output_aab: std.Build.LazyPath,
output_apks: std.Build.LazyPath,

pub fn create(
    b: *std.Build,
    app_name: anytype,
    key_store: InstallAndroidKeyStore,
    combo_lib: *std.Build.Step.InstallArtifact,
    manifest: *std.Build.Step.WriteFile,
    android_sdk: auto_detect.AndroidSDKConfig,
    bundletool: *FetchFile,
) *CreateAndroidAppBundle {
    const self = b.allocator.create(CreateAndroidAppBundle) catch @panic("OOM");
    self.combo_lib = combo_lib;
    self.manifest_wf = manifest;

    const aapt2_exe_path = b.pathJoin(&.{
        android_sdk.android_sdk_root,
        "build-tools",
        android_sdk.toolchain_version.build_tools_version,
        "aapt2",
    });

    const generate_resources_cmd = b.addSystemCommand(&.{ aapt2_exe_path, "compile", "--dir" });
    generate_resources_cmd.addDirectoryArg(.{ .path = b.pathJoin(&.{ "android", "res" }) });
    generate_resources_cmd.addArg("-o");
    self.compiled_resources_dir = generate_resources_cmd.addOutputFileArg("compiled_resources/");
    generate_resources_cmd.step.dependOn(&manifest.step);
    generate_resources_cmd.setName("aapt2 compile");

    self.generate_compiled_resource_step = Step.init(.{
        .id = .custom,
        .name = "GenerateCompiledResources",
        .owner = b,
    });
    self.generate_compiled_resource_step.dependOn(&generate_resources_cmd.step);

    self.list_files_from_compiled_resources_step = Step.init(.{
        .id = .custom,
        .name = "ListFilesFromCompiledResources",
        .owner = b,
        .makeFn = addFilesInResourcesToPreBundleCmd,
    });
    self.list_files_from_compiled_resources_step.dependOn(&self.generate_compiled_resource_step);

    self.generate_pre_bundle_cmd = b.addSystemCommand(&.{
        aapt2_exe_path,
        "link",
        "--auto-add-overlay",
        "--proto-format",
        "--output-to-dir",
        "-o",
    });
    self.link_output_dir = self.generate_pre_bundle_cmd.?.addOutputFileArg("output/");
    self.generate_pre_bundle_cmd.?.addArg("-I");
    self.generate_pre_bundle_cmd.?.addFileArg(.{
        .path = b.pathJoin(&.{
            android_sdk.android_sdk_root,
            "platforms",
            b.fmt("android-{s}", .{android_sdk.toolchain_version.api_version}),
            "android.jar",
        }),
    });
    self.generate_pre_bundle_cmd.?.addArg("--manifest");
    self.generate_pre_bundle_cmd.?.addFileArg(manifest.files.getLast().getPath());
    self.generate_pre_bundle_cmd.?.addArg("-R");
    self.generate_pre_bundle_cmd.?.step.dependOn(&self.list_files_from_compiled_resources_step);

    self.generate_pre_bundle_step = Step.init(.{
        .id = .custom,
        .name = "GeneratePreBundle",
        .owner = b,
    });
    self.generate_pre_bundle_step.dependOn(&self.generate_pre_bundle_cmd.?.step);

    self.copy_into_second_pre_bundle_step = Step.init(.{
        .id = .custom,
        .name = "CopyIntoPreBundle",
        .owner = b,
        .makeFn = copyFilesIntoSecondPreBundle,
    });
    self.copy_into_second_pre_bundle_step.dependOn(&self.generate_pre_bundle_step);

    self.second_pre_bundle_input_folder = b.addWriteFiles();
    self.second_pre_bundle_input_folder.?.step.dependOn(&self.copy_into_second_pre_bundle_step);

    const lib_location = combo_lib.artifact.getEmittedBin();
    const lib_name = combo_lib.artifact.out_lib_filename;
    const target = combo_lib.artifact.rootModuleTarget();

    const lib_dir_name = switch (target.cpu.arch) {
        .aarch64 => "arm64-v8a",
        .x86_64 => "x86_64",
        else => @panic("unsupported arch for android build"),
    };

    _ = self.second_pre_bundle_input_folder.?.addCopyFile(
        lib_location,
        b.pathJoin(&.{ "lib", lib_dir_name, lib_name }),
    );

    var zip_files = b.addSystemCommand(&.{ "zip", "-D4r" });
    const output_zip = zip_files.addOutputFileArg("second_pre_bundle.zip");
    zip_files.addArg(".");
    zip_files.step.dependOn(&self.second_pre_bundle_input_folder.?.step);
    zip_files.setCwd(self.second_pre_bundle_input_folder.?.getDirectory());

    self.generate_second_pre_bundle_step = Step.init(.{
        .id = .custom,
        .name = "GenerateSecondPreBundle",
        .owner = b,
    });
    self.generate_second_pre_bundle_step.dependOn(&zip_files.step);

    const generate_app_bundle_cmd = b.addSystemCommand(&.{ android_sdk.java_exe_path, "-jar" });
    generate_app_bundle_cmd.addFileArg(bundletool.destination);
    generate_app_bundle_cmd.addArgs(&.{ "build-bundle", "--modules" });
    generate_app_bundle_cmd.step.dependOn(&self.generate_second_pre_bundle_step);
    generate_app_bundle_cmd.step.dependOn(&bundletool.step);
    generate_app_bundle_cmd.addFileArg(output_zip);
    generate_app_bundle_cmd.addArg("--output");
    self.output_aab = generate_app_bundle_cmd.addOutputFileArg(app_name ++ ".aab");

    self.generate_app_bundle_step = Step.init(.{
        .id = .custom,
        .name = "GenerateAppBundle",
        .owner = b,
    });
    self.generate_app_bundle_step.dependOn(&generate_app_bundle_cmd.step);

    const generate_apks_cmd = b.addSystemCommand(&.{ android_sdk.java_exe_path, "-jar" });
    generate_apks_cmd.addFileArg(bundletool.destination);
    generate_apks_cmd.addArgs(&.{ "build-apks", "--overwrite", "--ks" });
    generate_apks_cmd.step.dependOn(key_store.step);
    generate_apks_cmd.step.dependOn(&bundletool.step);
    generate_apks_cmd.addFileArg(key_store.keystore_artifact);
    generate_apks_cmd.addArgs(&.{
        "--ks-key-alias",
        key_store.alias,
        "--key-pass",
        b.fmt("pass:{s}", .{key_store.keypass}),
        "--ks-pass",
        b.fmt("pass:{s}", .{key_store.keypass}),
        "--bundle",
    });
    generate_apks_cmd.step.dependOn(&self.generate_app_bundle_step);
    generate_apks_cmd.addFileArg(self.output_aab);
    generate_apks_cmd.addArg("--output");
    self.output_apks = generate_apks_cmd.addOutputFileArg(app_name ++ ".apks");
    const install_apks = b.addInstallFile(self.output_apks, app_name ++ ".apks");
    install_apks.step.dependOn(&generate_apks_cmd.step);

    self.generate_apks_step = Step.init(.{
        .id = .custom,
        .name = "GenerateApks",
        .owner = b,
    });
    self.generate_apks_step.dependOn(&generate_apks_cmd.step);

    self.step = Step.init(.{
        .id = .custom,
        .name = "CreateAndroidAppBundle",
        .owner = b,
    });
    self.step.dependOn(&self.generate_apks_step);

    return self;
}

fn copyFilesIntoSecondPreBundle(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const self: *CreateAndroidAppBundle = @fieldParentPtr("step", step);
    const b = step.owner;

    const prebundle_path = self.link_output_dir.?.getPath(b);

    _ = self.second_pre_bundle_input_folder.?.addCopyFile(
        .{ .path = b.pathJoin(&.{ prebundle_path, "AndroidManifest.xml" }) },
        "manifest/AndroidManifest.xml",
    );
    _ = self.second_pre_bundle_input_folder.?.addCopyFile(
        .{ .path = b.pathJoin(&.{ prebundle_path, "resources.pb" }) },
        "resources.pb",
    );

    const dir_path = b.pathJoin(&.{ prebundle_path, "res" });

    var dir = try fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |*entry| {
        const name = b.pathJoin(&.{ dir_path, entry.name });
        _ = self.second_pre_bundle_input_folder.?.addCopyFile(
            .{ .path = name },
            b.pathJoin(&.{ "res", entry.name }),
        );
    }
}

fn addFilesInResourcesToPreBundleCmd(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const self: *CreateAndroidAppBundle = @fieldParentPtr("step", step);

    const dir_path = self.compiled_resources_dir.?.getPath(step.owner);
    var dir = try fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |*entry| {
        const name = step.owner.pathJoin(&.{ dir_path, entry.name });

        const lazy_file = .{ .path = name };
        self.generate_pre_bundle_cmd.?.addFileArg(lazy_file);
    }
}
