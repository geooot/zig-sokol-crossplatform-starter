const ListFiles = @This();
const std = @import("std");
const Step = std.Build.Step;
const fs = std.fs;
const mem = std.mem;

step: Step,
directory: std.Build.LazyPath,

callback: *const fn (file: std.Build.LazyPath, state: *anyopaque) void,
state: *opaque {},

finished: bool = false,

pub const base_id = .custom;

pub fn create(
    owner: *std.Build,
    directory: std.Build.LazyPath,
    callback: *const fn (file: std.Build.LazyPath, state: *anyopaque) void,
    state: *opaque {},
) *ListFiles {
    const self = owner.allocator.create(ListFiles) catch @panic("OOM");
    self.* = .{
        .step = Step.init(.{
            .id = .custom,
            .name = "ListFiles",
            .owner = owner,
            .makeFn = make,
        }),
        .directory = directory,
        .callback = callback,
        .state = @ptrCast(state),
    };
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    const self: *ListFiles = @fieldParentPtr("step", step);

    const dir_path = self.directory.getPath(step.owner);

    var dir = try fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |*entry| {
        const name = step.owner.pathJoin(&.{ dir_path, entry.name });

        const lazy_file = step.owner.path(name);
        self.callback(lazy_file, self.state);
    }

    self.finished = true;
}
