const std = @import("std");

const Error = @import("Interpreter.zig").Error;
const runtime = @import("runtime.zig");

pub fn arrayPush(this: ?runtime.RuntimeValue, values: []const runtime.RuntimeValue, env: *runtime.Environment) Error!runtime.RuntimeValue {
    _ = env;
    var array = this.?.Array;
    // TODO: Handle errors.
    try array.appendSlice(values);
    return .Void;
}
