const FindAndroidSdk = @This();
const std = @import("std");
const ad = @import("./auto-detect.zig");
const Step = std.Build.Step;
const mem = std.mem;

step: Step,
versions: ad.ToolchainVersions,
target: std.zig.CrossTarget,

sdk: ad.AndroidSDKConfig = .{},

pub const base_id = .custom;

pub fn create(owner: *std.Build, target: std.zig.CrossTarget, versions: ad.ToolchainVersions) *FindAndroidSdk {
    const self = owner.allocator.create(FindAndroidSdk) catch @panic("OOM");
    self.* = .{
        .step = Step.init(.{
            .id = .custom,
            .name = "FindAndroidSdk",
            .owner = owner,
            .makeFn = make,
        }),
        .versions = versions,
        .target = target,
    };

    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    const self = @fieldParentPtr(FindAndroidSdk, "step", step);

    self.sdk = try ad.findAndroidSDKConfig(step.owner, &self.target, self.versions);
}
