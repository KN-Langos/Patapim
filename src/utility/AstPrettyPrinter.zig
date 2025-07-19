const std = @import("std");

const ansi = @import("reportz").ansi;

const common = @import("../common.zig");
const ast = @import("../parse/ast.zig");
const visitor = @import("../visitor.zig");

const Visitor = visitor.Visitor(ast.Node, @This(), anyerror, void{});
pub usingnamespace Visitor;

writer: std.io.AnyWriter,
print_spans: bool = true,
print_ids: bool = true,
indent: usize = 0,
current_nodeid: usize = 0, // This will be modified by visitor.

const Self = @This();

fn writeSpan(self: *Self, span: common.Span) !void {
    if (self.print_spans)
        try self.writer.print("{}@{d}:{d}{}", .{
            ansi.Style{ .foreground = .{ .basic = .cyan } },
            span.start,
            span.end,
            ansi.Style{ .modifiers = .{ .reset = true } },
        });

    if (self.print_ids)
        try self.writer.print("{}#{d}{}", .{
            ansi.Style{ .foreground = .{ .basic = .bright_cyan } },
            self.current_nodeid,
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

pub fn visitIntegerLiteral(self: *Self, tree: *const ast.Tree, span: common.Span, value: u64, visitee: anytype) !void {
    _ = tree;
    _ = span;
    _ = visitee;

    try self.writer.print("{}{d}{}", .{
        ansi.Style{ .foreground = .{ .basic = .bright_blue } },
        value,
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
}

pub fn visitFloatLiteral(self: *Self, tree: *const ast.Tree, span: common.Span, value: f64, visitee: anytype) !void {
    _ = tree;
    _ = span;
    _ = visitee;

    try self.writer.print("{}{d}{}", .{
        ansi.Style{ .foreground = .{ .basic = .bright_blue } },
        value,
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
}

pub fn visitBooleanLiteral(self: *Self, tree: *const ast.Tree, span: common.Span, value: bool, visitee: anytype) !void {
    _ = tree;
    _ = span;
    _ = visitee;

    try self.writer.print("{}{any}{}", .{
        ansi.Style{ .foreground = .{ .basic = .bright_blue } },
        value,
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
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

pub fn visitReturnStmt(self: *Self, tree: *const ast.Tree, span: common.Span, ret: ast.ReturnStatement, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}return", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    if (ret.value) |value| {
        try self.writer.writeByte(' ');
        try self.accept(tree, value);
    }
    try self.writer.writeByte('\n');
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

pub fn visitVariable(self: *Self, tree: *const ast.Tree, span: common.Span, variable: ast.Variable, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}brr", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');

    try self.accept(tree, variable.name);
    try self.writer.writeAll(" = ");
    try self.accept(tree, variable.expression);
    try self.writer.writeByte('\n');
}

pub fn visitConstant(self: *Self, tree: *const ast.Tree, span: common.Span, variable: ast.Const, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}const", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');

    try self.accept(tree, variable.name);
    try self.writer.writeAll(" = ");
    try self.accept(tree, variable.expression);
    try self.writer.writeByte('\n');
}

pub fn visitBinaryOperator(self: *Self, tree: *const ast.Tree, span: common.Span, expr: ast.BinaryOperator, visitee: anytype) !void {
    _ = visitee;

    try self.writer.writeByte('(');
    try self.accept(tree, expr.left);
    try self.writer.print(" {}{s}{} ", .{
        ansi.Style{ .foreground = .{ .basic = .bright_magenta } },
        @tagName(expr.operator),
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.accept(tree, expr.right);
    try self.writer.writeByte(')');
    try self.writeSpan(span);
}

pub fn visitUnaryOperator(self: *Self, tree: *const ast.Tree, span: common.Span, expr: ast.UnaryOperator, visitee: anytype) !void {
    _ = visitee;

    try self.writer.writeByte('(');
    try self.writer.print("{}{s}{} ", .{
        ansi.Style{ .foreground = .{ .basic = .bright_magenta } },
        @tagName(expr.operator),
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.accept(tree, expr.operand);
    try self.writer.writeByte(')');
    try self.writeSpan(span);
}

pub fn visitArrayLiteral(self: *Self, tree: *const ast.Tree, span: common.Span, lit: ast.ArrayLiteral, visitee: anytype) !void {
    _ = visitee;

    try self.writer.writeByte('[');
    for (lit.elements) |elem| {
        try self.accept(tree, elem);
        try self.writer.writeAll(", ");
    }
    if (lit.spread) |spread| {
        try self.writer.writeAll("...");
        try self.accept(tree, spread);
    }
    try self.writer.writeByte(']');
    try self.writeSpan(span);
}

pub fn visitStructDecl(self: *Self, tree: *const ast.Tree, span: common.Span, decl: ast.StructDecl, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}struct", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');

    try self.accept(tree, decl.name);

    try self.writer.writeAll(" {\n");
    self.indent += 4;
    for (decl.fields) |field| {
        try self.writeIndent();
        try self.accept(tree, field);
        try self.writer.writeAll(",\n");
    }
    for (decl.decls) |fn_decl| {
        try self.accept(tree, fn_decl);
    }
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}\n");
}

pub fn visitEnumDecl(self: *Self, tree: *const ast.Tree, span: common.Span, decl: ast.EnumDecl, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}enum", .{ansi.Style{ .foreground = .{ .basic = .yellow } }});
    try self.writeSpan(span);
    try self.writer.writeByte(' ');

    try self.accept(tree, decl.name);

    try self.writer.writeAll(" {\n");
    self.indent += 4;
    for (decl.variants) |variant| {
        try self.writeIndent();
        try self.accept(tree, variant);
        try self.writer.writeAll(",\n");
    }
    for (decl.decls) |fn_decl| {
        try self.accept(tree, fn_decl);
    }
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}\n");
}

pub fn visitExprStmt(self: *Self, tree: *const ast.Tree, span: common.Span, expr: usize, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    try self.writeIndent();
    try self.accept(tree, expr);
    try self.writer.writeAll(";\n");
}

pub fn visitFunctionCall(self: *Self, tree: *const ast.Tree, span: common.Span, call: ast.FunctionCall, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    try self.accept(tree, call.target);
    try self.writer.writeByte('(');
    for (call.arguments) |arg| {
        try self.accept(tree, arg);
        try self.writer.writeAll(", ");
    }
    try self.writer.writeByte(')');
}

pub fn visitMemberAccess(self: *Self, tree: *const ast.Tree, span: common.Span, access: ast.MemberAccess, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    try self.accept(tree, access.target);
    try self.writer.writeByte('.');
    try self.accept(tree, access.member);
}

pub fn visitIndexedAccess(self: *Self, tree: *const ast.Tree, span: common.Span, access: ast.IndexedAccess, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    try self.accept(tree, access.target);
    try self.writer.writeByte('[');
    try self.accept(tree, access.index);
    try self.writer.writeByte(']');
}

pub fn visitConditional(self: *Self, tree: *const ast.Tree, span: common.Span, cond: ast.Conditional, visitee: anytype) !void {
    _ = visitee;

    if (cond.condition != null) {
        try self.writeIndent();
        try self.writer.print("{}if{}", .{
            ansi.Style{ .foreground = .{ .basic = .yellow } },
            ansi.Style{ .modifiers = .{ .reset = true } },
        });
    }
    try self.writeSpan(span);
    if (cond.condition) |condition| {
        try self.writer.writeByte('(');
        try self.accept(tree, condition);
        try self.writer.writeByte(')');
    }
    try self.writer.writeAll(" {\n");
    self.indent += 4;
    try self.accept(tree, cond.body);
    self.indent -= 4;
    try self.writeIndent();

    if (cond.else_conditional) |else_cond| {
        try self.writer.print("}} {}else{}", .{
            ansi.Style{ .foreground = .{ .basic = .yellow } },
            ansi.Style{ .modifiers = .{ .reset = true } },
        });
        try self.accept(tree, else_cond);
    } else {
        try self.writer.writeAll("}\n");
    }
}

pub fn visitLoop(self: *Self, tree: *const ast.Tree, span: common.Span, loop: ast.Loop, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}loop{}", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
    try self.writer.writeAll(" {\n");
    self.indent += 4;
    try self.accept(tree, loop.body);
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}\n");
}

pub fn visitWhileLoop(self: *Self, tree: *const ast.Tree, span: common.Span, loop: ast.WhileLoop, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}while{}", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
    try self.writer.writeByte('(');
    try self.accept(tree, loop.condition);
    try self.writer.writeByte(')');

    try self.writer.writeAll(" {\n");
    self.indent += 4;
    try self.accept(tree, loop.body);
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}\n");
}

pub fn visitForLoop(self: *Self, tree: *const ast.Tree, span: common.Span, loop: ast.ForLoop, visitee: anytype) !void {
    _ = visitee;

    try self.writeIndent();
    try self.writer.print("{}for{}", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
    try self.writer.writeByte('(');
    try self.accept(tree, loop.binding);
    try self.writer.print(" {}in{} ", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.accept(tree, loop.iterable);
    try self.writer.writeByte(')');

    try self.writer.writeAll(" {\n");
    self.indent += 4;
    try self.accept(tree, loop.body);
    self.indent -= 4;
    try self.writeIndent();
    try self.writer.writeAll("}\n");
}

pub fn visitInlineConditional(self: *Self, tree: *const ast.Tree, span: common.Span, cond: ast.InlineConditional, visitee: anytype) !void {
    _ = visitee;

    try self.writer.print("{}if{}", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.writeSpan(span);
    try self.writer.writeByte('(');
    try self.accept(tree, cond.condition);
    try self.writer.writeAll(") ");

    try self.accept(tree, cond.then_expr);
    try self.writer.print(" {}else{} ", .{
        ansi.Style{ .foreground = .{ .basic = .yellow } },
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.accept(tree, cond.else_expr);
}

pub fn visitAssignment(self: *Self, tree: *const ast.Tree, span: common.Span, expr: ast.Assignment, visitee: anytype) !void {
    _ = visitee;

    try self.writer.writeByte('(');
    try self.accept(tree, expr.target);
    try self.writer.print(" {}{}{} ", .{
        ansi.Style{ .foreground = .{ .basic = .bright_magenta } },
        try self.writer.writeByte('='),
        ansi.Style{ .modifiers = .{ .reset = true } },
    });
    try self.accept(tree, expr.value);
    try self.writer.writeByte(')');
    try self.writeSpan(span);
}

pub fn visitStructLiteral(self: *Self, tree: *const ast.Tree, span: common.Span, lit: ast.StructLiteral, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    if (lit.target) |target| {
        try self.accept(tree, target);
    } else {
        try self.writer.writeByte('#');
    }
    try self.writer.writeAll(" { ");
    for (lit.fields) |field| {
        try self.accept(tree, field);
        try self.writer.writeAll(", ");
    }
    try self.writer.writeByte('}');
}

pub fn visitFieldDef(self: *Self, tree: *const ast.Tree, span: common.Span, def: ast.FieldDef, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    try self.accept(tree, def.name);
    try self.writer.writeAll(": ");
    try self.accept(tree, def.value);
}
