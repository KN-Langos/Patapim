//! This file will contain the CLI tool for Patapim.
//! Main interpreter source code has root in `root.zig`

const std = @import("std");

const patapim = @import("patapim");

pub fn main() !void {
    std.debug.print("All your code belongs to Patapim!\n", .{});
}
