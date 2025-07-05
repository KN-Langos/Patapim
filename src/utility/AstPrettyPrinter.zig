const std = @import("std");

const ansi = @import("reportz").ansi;

const common = @import("../common.zig");
const ast = @import("../parse/ast.zig");
const visitor = @import("../visitor.zig");

const Visitor = visitor.Visitor(ast.Node, @This(), anyerror, void{});
pub usingnamespace Visitor;

writer: std.io.AnyWriter,
print_spans: bool = true,
indent: usize = 0,

const Self = @This();

fn writeSpan(self: *Self, span: common.Span) !void {
    if (!self.print_spans) return;
    try self.writer.print("{}@{d}:{d}{}", .{
        ansi.Style{ .foreground = .{ .basic = .cyan } },
        span.start,
        span.end,
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
}

fn writeIndent(self: *Self) !void {
    try self.writer.writeByteNTimes(' ', self.indent);
}

pub fn visitIdentifier(self: *Self, tree: *const ast.Tree, span: common.Span, content: []const u8, visitee: anytype) !void {
    _ = tree;
    _ = visitee;

    try self.writer.print("{}{s}{}", .{
        ansi.Style{ .foreground = .{ .basic = .bright_blue } },
        content,
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
}

pub fn visitStringLiteral(self: *Self, tree: *const ast.Tree, span: common.Span, content: []const u8, visitee: anytype) !void {
    _ = tree;
    _ = visitee;

    try self.writer.print("{}\"{s}\"{}", .{
        ansi.Style{ .foreground = .{ .basic = .bright_green } },
        content,
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
}

pub fn visitModule(self: *Self, tree: *const ast.Tree, span: common.Span, mod: ast.Module, visitee: anytype) !void {
    _ = mod;

    try self.writeIndent();
    try self.writer.print("{}module{}", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
    try self.writer.writeAll(" {\n");
    self.indent += 4;
    try visitee.walk(tree);
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}");
}

pub fn visitImport(self: *Self, tree: *const ast.Tree, span: common.Span, import: ast.Import, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}import", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');
    try self.accept(tree, import.source);
    if (import.opt_rename) |rename| {
        try self.writer.print(" {}as ", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
        try self.accept(tree, rename);
    }
    try self.writer.writeByte('\n');
}

pub fn visitFunctionDef(self: *Self, tree: *const ast.Tree, span: common.Span, def: ast.FunctionDef, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}fn", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');

    try self.accept(tree, def.name);
    try self.writer.writeByte('(');
    for (def.parameters) |param| {
        try self.accept(tree, param);
        try self.writer.writeAll(", ");
    }
    try self.writer.writeAll(") {\n");
    self.indent += 4;
    try self.accept(tree, def.body);
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}\n");
}

pub fn visitNativeFunctionDecl(self: *Self, tree: *const ast.Tree, span: common.Span, decl: ast.NativeFunctionDecl, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}native", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');
    if (decl.abi) |abi| {
        try self.accept(tree, abi);
    }
    try self.writer.print(" {}fn", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writer.writeByte(' ');

    try self.accept(tree, decl.name);
    try self.writer.writeByte('(');
    for (decl.parameters) |param| {
        try self.accept(tree, param);
        try self.writer.writeAll(", ");
    }
    try self.writer.writeAll(")\n");
}

pub fn visitNativeParameter(self: *Self, tree: *const ast.Tree, span: common.Span, param: ast.NativeParameter, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    try self.accept(tree, param.name);
    if (param.type) |typ| {
        try self.writer.writeAll(": ");
        try self.accept(tree, typ);
    }
}
