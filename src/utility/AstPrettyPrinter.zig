const std = @import("std");

const common = @import("../common.zig");
const ast = @import("../parse/ast.zig");
const visitor = @import("../visitor.zig");

const Visitor = visitor.Visitor(ast.Node, @This(), anyerror, void{});
pub usingnamespace Visitor;

const Self = @This();

pub fn visitModule(self: *Self, tree: *const ast.Tree, span: common.Span, mod: ast.Module, visitee: anytype) !void {
    _ = self;
    _ = span;
    _ = mod;

    std.debug.print("Visiting module!!\n", .{});
    try visitee.walk(tree);
}
