const std = @import("std");
pub const uringbuf = @import("./uringbuf.zig");
pub const ulog = @import("./ulog.zig");

comptime {
    // this forces the C export of the functions in these files
    std.testing.refAllDecls(ulog);
    std.testing.refAllDecls(uringbuf);
}
