//! This is the main implementation of Patapim programming language interpreter.
//! This contains lexer, parser, and other passes.

const std = @import("std");

pub const Lexer = @import("Lexer.zig");
pub const ast = @import("parse/ast.zig");
pub const Parser = @import("parse/Parser.zig");
pub const Interpreter = @import("interpreter/Interpreter.zig");
pub const runtime = @import("interpreter/runtime.zig");

pub const analysis = struct {
    pub const Metadata = @import("analysis/Metadata.zig");
    pub const ItemNameBindingPass = @import("analysis/ItemNameBindingPass.zig");
    pub const NameResolutionPass = @import("analysis/NameResolutionPass.zig");
};

// Above are temporary public imports. Used for testing until there is proper library API.

test {
    _ = @import("Lexer.zig");
    _ = @import("parse/Parser.zig");
    _ = @import("parse/ast.zig");
    _ = @import("interpreter/Interpreter.zig");
    _ = @import("interpreter/runtime.zig");
    _ = @import("analysis/Metadata.zig");
    _ = @import("analysis/ItemNameBindingPass.zig");
    _ = @import("analysis/NameResolutionPass.zig");
}
