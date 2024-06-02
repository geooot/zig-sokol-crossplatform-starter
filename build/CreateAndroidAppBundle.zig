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

generate_pre_bundle_cmd: *std.Build.Step.Run,
linked_resources_folder: std.Build.LazyPath,
second_pre_bundle_input_wf: *std.Build.Step.WriteFile,

output_aab: std.Build.LazyPath,
output_apks: std.Build.LazyPath,

pub fn create(
    b: *std.Build,
    app_name: []const u8,
    key_store: InstallAndroidKeyStore,
    combo_lib: *std.Build.Step.InstallArtifact,
    manifest: *std.Build.Step.WriteFile,
    android_sdk: auto_detect.AndroidSDKConfig,
    bundletool: *FetchFile,
    zipcreate: *std.Build.Step.Compile,
    zipextract: *std.Build.Step.Compile,
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
    const compiled_resources_zip = generate_resources_cmd.addOutputFileArg("compiled_resources.zip");
    generate_resources_cmd.step.dependOn(&manifest.step);
    generate_resources_cmd.setName("aapt2 compile");

    self.generate_compiled_resource_step = Step.init(.{
        .id = .custom,
        .name = "GenerateCompiledResources",
        .owner = b,
    });
    self.generate_compiled_resource_step.dependOn(&generate_resources_cmd.step);

    self.generate_pre_bundle_cmd = b.addSystemCommand(&.{
        aapt2_exe_path,
        "link",
        "--auto-add-overlay",
        "--proto-format",
        "-o",
    });
    const linked_resources_zip_wf = b.addWriteFiles();
    const linked_resources_zip = linked_resources_zip_wf.add("linked_resources.zip", "");
    self.generate_pre_bundle_cmd.addFileArg(linked_resources_zip);
    self.generate_pre_bundle_cmd.addArg("-I");
    self.generate_pre_bundle_cmd.addFileArg(.{
        .path = b.pathJoin(&.{
            android_sdk.android_sdk_root,
            "platforms",
            b.fmt("android-{s}", .{android_sdk.toolchain_version.api_version}),
            "android.jar",
        }),
    });
    self.generate_pre_bundle_cmd.addArg("--manifest");
    self.generate_pre_bundle_cmd.addFileArg(manifest.files.getLast().getPath());
    self.generate_pre_bundle_cmd.addFileArg(compiled_resources_zip);
    self.generate_pre_bundle_cmd.step.dependOn(&self.generate_compiled_resource_step);
    self.generate_pre_bundle_cmd.step.dependOn(&linked_resources_zip_wf.step);

    const linked_resources_wf = b.addWriteFiles();

    const unzip_linked_resources = b.addRunArtifact(zipextract);
    unzip_linked_resources.addFileArg(linked_resources_zip);
    unzip_linked_resources.addDirectoryArg(linked_resources_wf.getDirectory());
    unzip_linked_resources.step.dependOn(&self.generate_pre_bundle_cmd.step);
    self.linked_resources_folder = linked_resources_wf.getDirectory();

    self.generate_pre_bundle_step = Step.init(.{
        .id = .custom,
        .name = "GeneratePreBundle",
        .owner = b,
    });
    self.generate_pre_bundle_step.dependOn(&unzip_linked_resources.step);

    self.copy_into_second_pre_bundle_step = Step.init(.{
        .id = .custom,
        .name = "CopyIntoPreBundle",
        .owner = b,
        .makeFn = copyFilesIntoSecondPreBundle,
    });
    self.copy_into_second_pre_bundle_step.dependOn(&self.generate_pre_bundle_step);

    self.second_pre_bundle_input_wf = b.addWriteFiles();
    self.second_pre_bundle_input_wf.step.dependOn(&self.copy_into_second_pre_bundle_step);

    const lib_location = combo_lib.artifact.getEmittedBin();
    const lib_name = combo_lib.artifact.out_lib_filename;
    const target = combo_lib.artifact.rootModuleTarget();

    const lib_dir_name = switch (target.cpu.arch) {
        .aarch64 => "arm64-v8a",
        .x86_64 => "x86_64",
        else => @panic("unsupported arch for android build"),
    };

    _ = self.second_pre_bundle_input_wf.addCopyFile(
        lib_location,
        b.pathJoin(&.{ "lib", lib_dir_name, lib_name }),
    );

    var zip_pre_bundle = b.addRunArtifact(zipcreate);
    const zipped_prebundle = zip_pre_bundle.addOutputFileArg("second_pre_bundle.zip");
    zip_pre_bundle.addDirectoryArg(self.second_pre_bundle_input_wf.getDirectory());
    zip_pre_bundle.addArg("");
    zip_pre_bundle.step.dependOn(&self.second_pre_bundle_input_wf.step);
    zip_pre_bundle.step.dependOn(&self.copy_into_second_pre_bundle_step);

    self.generate_second_pre_bundle_step = Step.init(.{
        .id = .custom,
        .name = "GenerateSecondPreBundle",
        .owner = b,
    });
    self.generate_second_pre_bundle_step.dependOn(&zip_pre_bundle.step);

    const generate_app_bundle_cmd = b.addSystemCommand(&.{ android_sdk.java_exe_path, "-jar" });
    generate_app_bundle_cmd.addFileArg(bundletool.destination);
    generate_app_bundle_cmd.addArgs(&.{ "build-bundle", "--modules" });
    generate_app_bundle_cmd.step.dependOn(&self.generate_second_pre_bundle_step);
    generate_app_bundle_cmd.step.dependOn(&bundletool.step);
    generate_app_bundle_cmd.addFileArg(zipped_prebundle);
    generate_app_bundle_cmd.addArg("--output");
    self.output_aab = generate_app_bundle_cmd.addOutputFileArg(b.fmt("{s}{s}", .{ app_name, ".aab" }));

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
    self.output_apks = generate_apks_cmd.addOutputFileArg(b.fmt("{s}{s}", .{ app_name, ".apks" }));
    const install_apks = b.addInstallFile(self.output_apks, b.fmt("{s}{s}", .{ app_name, ".apks" }));
    install_apks.step.dependOn(&generate_apks_cmd.step);

    self.generate_apks_step = Step.init(.{
        .id = .custom,
        .name = "GenerateApks",
        .owner = b,
    });
    self.generate_apks_step.dependOn(&install_apks.step);

    self.step = Step.init(.{
        .id = .custom,
        .name = "CreateAndroidAppBundle",
        .owner = b,
    });
    self.step.dependOn(&self.generate_apks_step);

    return self;
}

const CopyFileReq = struct {
    src: []u8,
    dest: []u8,
};

const Error = error{InvalidFileKind};

fn copyFilesIntoSecondPreBundle(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const self: *CreateAndroidAppBundle = @fieldParentPtr("copy_into_second_pre_bundle_step", step);
    const b = step.owner;

    const prebundle_path = self.linked_resources_folder.getPath(b);

    _ = self.second_pre_bundle_input_wf.addCopyFile(
        .{ .path = b.pathJoin(&.{ prebundle_path, "AndroidManifest.xml" }) },
        "manifest/AndroidManifest.xml",
    );
    _ = self.second_pre_bundle_input_wf.addCopyFile(
        .{ .path = b.pathJoin(&.{ prebundle_path, "resources.pb" }) },
        "resources.pb",
    );

    const dir_path = b.pathJoin(&.{ prebundle_path, "res" });

    var paths = std.ArrayList(CopyFileReq).init(b.allocator);
    try paths.append(.{
        .src = dir_path,
        .dest = @constCast("res"),
    });

    var curr_path = paths.popOrNull();
    while (curr_path) |p| : (curr_path = paths.popOrNull()) {
        const local_file = try std.fs.cwd().openFile(p.src, .{ .mode = .read_only });
        defer local_file.close();

        const local_file_stat = try local_file.stat();

        try switch (local_file_stat.kind) {
            .file => {
                _ = self.second_pre_bundle_input_wf.addCopyFile(
                    .{ .path = p.src },
                    p.dest,
                );
            },
            .directory => {
                const local_dir = try std.fs.cwd().openDir(p.src, .{ .iterate = true });
                var iter = local_dir.iterate();

                while (try iter.next()) |entry| {
                    try paths.append(.{
                        .src = b.pathJoin(&.{ p.src, entry.name }),
                        .dest = b.pathJoin(&.{ p.dest, entry.name }),
                    });
                }
            },
            else => Error.InvalidFileKind,
        };
    }
}
