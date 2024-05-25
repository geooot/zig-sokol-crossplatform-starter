const kz = @import("kubazipc");
const std = @import("std");

const READ_BUFFER_SIZE = 4096;

const Error = error{
    FailedToCopyZip,
    FailedToWriteEntry,
    FileNotFound,
    FailedToCreateEntry,
    InvalidFileKind,
    Overflow,
    OutOfMemory,
    InvalidCmdLine,
} || std.fs.File.OpenError || std.fs.File.StatError || std.fs.File.ReadError;

const Pairing = struct {
    local_path: []const u8,
    zip_dest_path: []const u8,
};

// zipcreate file.zip local_path zip_path
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpalloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpalloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 3)
        return 1;

    const zip_file = args[1];
    const paths = args[2..];
    var list = std.ArrayList(Pairing).init(allocator);

    errdefer |e| switch (@as(Error, e)) {
        error.FileNotFound => std.log.err("could not find zip file {s}", .{zip_file}),
        else => {},
    };

    const zip = kz.zip_open(zip_file, 6, 'w') orelse return error.FileNotFound;
    defer kz.zip_close(zip);

    var i: usize = 0;
    while (i < paths.len) : (i += 2) {
        if (i + 1 >= paths.len) break;

        const local_path = paths[i];
        const zip_dest_path = paths[i + 1];
        try list.append(.{
            .local_path = local_path,
            .zip_dest_path = zip_dest_path,
        });
    }

    var pair = list.popOrNull();
    while (pair) |p| : (pair = list.popOrNull()) {
        const local_path = p.local_path;
        const zip_dest_path = p.zip_dest_path;

        errdefer std.log.err("error while processing local_path=\"{s}\", zip_dest_path\"{s}\"", .{ local_path, zip_dest_path });

        const local_file = try std.fs.cwd().openFile(local_path, .{ .mode = .read_only });
        defer local_file.close();

        const local_file_stat = try local_file.stat();

        try switch (local_file_stat.kind) {
            .file => blk: {
                const zip_dest_path_c_str: [:0]u8 = @ptrCast(try std.fmt.allocPrint(allocator, "{s}\x00", .{zip_dest_path}));
                if (kz.zip_entry_open(zip, zip_dest_path_c_str) < 0) {
                    break :blk error.FailedToCreateEntry;
                }
                defer _ = kz.zip_entry_close(zip);

                var read_amt: usize = 1;
                var buffer: [READ_BUFFER_SIZE]u8 = undefined;
                while (read_amt > 0) {
                    read_amt = try local_file.read(&buffer);
                    if (kz.zip_entry_write(zip, &buffer, read_amt) < 0) {
                        break :blk error.FailedToWriteEntry;
                    }
                }
            },
            .directory => {
                const local_dir = try std.fs.cwd().openDir(local_path, .{ .iterate = true });
                var iter = local_dir.iterate();

                while (try iter.next()) |entry| {
                    const new_local_file = try std.fs.path.join(allocator, &.{ local_path, entry.name });
                    const new_zip_dest_path = try std.fs.path.join(allocator, &.{ zip_dest_path, entry.name });
                    try list.append(.{
                        .local_path = new_local_file,
                        .zip_dest_path = new_zip_dest_path,
                    });
                }
            },
            else => error.InvalidFileKind,
        };
    }

    return 0;
}
