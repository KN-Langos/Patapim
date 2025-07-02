//! This is the main implementation of Patapim programming language interpreter.
//! This contains lexer, parser, and other passes.

const std = @import("std");

test {
    // This ensures that all submodules are referenced when compiling tests
    // to prevent tree shaking from removing tests.
    std.testing.refAllDeclsRecursive(@This());
}
