const cube = @import("core/cube.zig");

const sokol = @import("sokol");
const sapp = sokol.app;

pub fn main() void {
    sapp.run(cube.app_descriptor);
}
