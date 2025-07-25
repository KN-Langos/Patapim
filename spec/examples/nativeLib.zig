// This is a Zig file that defines a native library for runtime values and a Fibonacci function.
// You can make your own native functions by defining them in this way.
const std = @import("std");

pub const RuntimeValue = union(enum) {
    Integer: i64,
    Float: f64,
    Boolean: bool,
    String: []const u8,
    Array: std.ArrayList(RuntimeValue),
    Void: void,
};

export fn add(args: [*]const RuntimeValue, args_len: usize, result: *RuntimeValue) callconv(.C) void {
    if (args_len != 2) {
        std.debug.panic("Expected 2 arguments for add, got {}", .{args_len});
    }

    const a = args[0].Integer;
    const b = args[1].Integer;

    result.* = RuntimeValue{ .Integer = a + b };
}
