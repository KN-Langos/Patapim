//! This is the main implementation of Patapim programming language interpreter.
//! This contains lexer, parser, and other passes.

const std = @import("std");

pub const Lexer = @import("Lexer.zig");
pub const ast = @import("parse/ast.zig");
pub const Parser = @import("parse/Parser.zig");

// Above are temporary public imports. Used for testing until there is proper library API.

test {
    // This ensures that all submodules are referenced when compiling tests
    // to prevent tree shaking from removing tests.
    std.testing.refAllDeclsRecursive(@This());
}
