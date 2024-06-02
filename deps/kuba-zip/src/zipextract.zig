const kz = @import("kubazipc");
const std = @import("std");

const Error = error{ExtractError};

// zipextract file.zip output_dir_path
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpalloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpalloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2)
        return 1;

    const zip_file = args[1];
    const output_dir_path = args[2];

    const errno = kz.zip_extract(zip_file, output_dir_path, null, null);

    if (errno < 0)
        return Error.ExtractError;

    return 0;
}
