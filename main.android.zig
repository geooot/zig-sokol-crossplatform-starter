const cube = @import("core/cube.zig");

const sokol = @import("sokol");
const sapp = sokol.app;

// Need this to be here in order for the resulting shared library to include
// the rest of the functions properly. Why? IDK!?
pub fn main() void {}

export fn sokol_main() sapp.Desc {
    return cube.app_descriptor;
}
