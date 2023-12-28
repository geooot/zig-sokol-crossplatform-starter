const FetchFile = @This();
const std = @import("std");
const Step = std.Build.Step;

step: Step,
url: []const u8,
destination: std.Build.LazyPath,

pub const base_id = .custom;

pub fn create(
    owner: *std.Build,
    url: []const u8,
    destination: std.Build.LazyPath,
) *FetchFile {
    const self = owner.allocator.create(FetchFile) catch @panic("OOM");
    self.* = .{
        .step = Step.init(.{
            .id = .custom,
            .name = "FetchFile",
            .owner = owner,
            .makeFn = make,
        }),
        .destination = destination,
        .url = url,
    };
    destination.addStepDependencies(&self.step);
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    const self = @fieldParentPtr(FetchFile, "step", step);
    const allocator = step.owner.allocator;

    const target_file_path = self.destination.getPath(step.owner);

    const target_file = try std.fs.openFileAbsolute(target_file_path, .{ .mode = .read_write });

    var man = step.owner.cache.obtain();
    defer man.deinit();

    man.hash.addBytes(self.url);
    _ = try man.addFile(target_file_path, null);

    if (try step.cacheHit(&man)) {
        return;
    }

    std.debug.print("Fetching \"{s}\" into \"{s}\"\n", .{ self.url, target_file_path });

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();
    var fetch_res = try client.fetch(allocator, .{
        .location = .{ .url = self.url },
        .response_strategy = .{ .file = target_file },
    });
    fetch_res.deinit();
    try step.writeManifest(&man);
}
