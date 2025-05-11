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

fn make(step: *Step, make_options: std.Build.Step.MakeOptions) !void {
    _ = make_options;
    const self: *FetchFile = @fieldParentPtr("step", step);
    const allocator = step.owner.allocator;

    const target_file_path = self.destination.getPath(step.owner);

    const target_file = try std.fs.openFileAbsolute(target_file_path, .{ .mode = .read_write });

    var man = step.owner.graph.cache.obtain();
    defer man.deinit();

    man.hash.addBytes(self.url);
    _ = try man.addFile(target_file_path, null);

    if (try step.cacheHit(&man)) {
        return;
    }

    std.debug.print("Fetching \"{s}\" into \"{s}\"\n", .{ self.url, target_file_path });

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();
    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    _ = try client.fetch(.{
        .location = .{ .url = self.url },
        .max_append_size = 28 * 1024 * 1024, // bundletool.zip is around 28MB
        .response_storage = .{ .dynamic = &body },
    });

    try target_file.writeAll(body.items);

    try step.writeManifest(&man);
}
