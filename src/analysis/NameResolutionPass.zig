//! This pass resolves variable and globals names.

const std = @import("std");

const reportz = @import("reportz");

const common = @import("../common.zig");
const ast = @import("../parse/ast.zig");
const visitor = @import("../visitor.zig");
const Metadata = @import("Metadata.zig");

pub const NameResolutionError = error{
    UnknownVariable,
} || std.mem.Allocator.Error;
const Visitor = visitor.Visitor(ast.Node, @This(), NameResolutionError, void{});
pub usingnamespace Visitor;

source_id: []const u8,
metadata: *Metadata,
current_nodeid: usize = 0, // This will be modified by visitor.

diagnostic_alloc: std.mem.Allocator, // This could be better.
diagnostic_log: std.ArrayList(reportz.reports.Diagnostic),

const Self = @This();
const LOG = std.log.scoped(.name_resolution_pass);

pub fn reportError(
    self: *Self,
    code: []const u8,
    comptime message_fmt: []const u8,
    message_args: anytype,
    error_type: Self.NameResolutionError,
    additional_options: struct {
        severity: reportz.reports.Severity = .@"error",
        labels: []const reportz.reports.Label,
        notes: []const reportz.reports.Note = &.{},
    },
) Self.NameResolutionError {
    @branchHint(.cold);

    const diagnostic_alloc = self.diagnostic_alloc;

    try self.diagnostic_log.append(reportz.reports.Diagnostic{
        .source_id = self.source_id,
        .severity = additional_options.severity,
        .code = code,
        .message = try std.fmt.allocPrint(diagnostic_alloc, message_fmt, message_args),
        // This ensures that labels and notes live at least as long as diagnostic_log field.
        .labels = try common.deepClone(
            []const reportz.reports.Label,
            additional_options.labels,
            diagnostic_alloc,
        ),
        .notes = try common.deepClone(
            []const reportz.reports.Note,
            additional_options.notes,
            diagnostic_alloc,
        ),
    });

    return error_type;
}

pub fn visitStructDecl(self: *Self, tree: *const ast.Tree, span: common.Span, def: ast.StructDecl, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    // Enter struct scope from struct.
    self.metadata.enterScope(
        self.metadata.references[self.current_nodeid],
    );

    var scope = self.metadata.currentScope();

    for (def.fields) |field| {
        const var_name = tree.getNodeUnsafe(field).kind.identifier;
        try scope.known_names.put(var_name, self.current_nodeid);
    }

    for (def.decls) |decl|
        try self.accept(tree, decl);

    _ = self.metadata.popScope();
}

pub fn visitFunctionDef(self: *Self, tree: *const ast.Tree, span: common.Span, def: ast.FunctionDef, visitee: anytype) !void {
    _ = visitee;
    _ = span;

    // Enter function scope from function.
    self.metadata.enterScope(
        self.metadata.references[self.current_nodeid],
    );

    for (def.parameters) |param|
        try self.accept(tree, param);
    try self.accept(tree, def.body);

    _ = self.metadata.popScope();
}

pub fn visitParameter(self: *Self, tree: *const ast.Tree, span: common.Span, param: ast.Parameter, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    // Register name on the current scope.
    var scope = self.metadata.currentScope();
    const param_name = tree.getNodeUnsafe(param.name).kind.identifier;
    try scope.known_names.put(param_name, self.current_nodeid);
}

pub fn visitVariable(self: *Self, tree: *const ast.Tree, span: common.Span, def: ast.Variable, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    try self.accept(tree, def.expression);
    var scope = self.metadata.currentScope();
    const var_name = tree.getNodeUnsafe(def.name).kind.identifier;
    try scope.known_names.put(var_name, self.current_nodeid);
}

pub fn visitConstant(self: *Self, tree: *const ast.Tree, span: common.Span, def: ast.Const, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    try self.accept(tree, def.expression);
    var scope = self.metadata.currentScope();
    const var_name = tree.getNodeUnsafe(def.name).kind.identifier;
    try scope.known_names.put(var_name, self.current_nodeid);
}

pub fn visitVariableRef(self: *Self, tree: *const ast.Tree, span: common.Span, ident: usize, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    const var_name = tree.getNodeUnsafe(ident).kind.identifier;

    if (std.mem.eql(u8, var_name, "this")) return;
    const found_ref = self.metadata.findName(var_name);
    if (found_ref) |found| {
        self.metadata.references[self.current_nodeid] = found;
        LOG.debug("Resolved variable '{s}'#{d} to reference #{d}.", .{
            var_name,
            self.current_nodeid,
            found,
        });
    } else {
        const node_span = tree.getNodeUnsafe(ident).span;
        return self.reportError(
            "A001",
            "Variable with name '{s}' does not exist here.",
            .{var_name},
            error.UnknownVariable,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .magenta },
                    .span = node_span.asReportz(),
                    .message = "Name referenced here.",
                }},
            },
        );
    }
}

pub fn visitConditional(self: *Self, tree: *const ast.Tree, span: common.Span, cond: ast.Conditional, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    // Analyze condition before entering scope.
    if (cond.condition) |condition|
        try self.accept(tree, condition);

    // Main body.
    const main_body = try self.metadata.pushScope();
    self.metadata.references[cond.body] = main_body;
    try self.accept(tree, cond.body);
    _ = self.metadata.popScope();

    if (cond.else_conditional) |else_cond|
        try self.accept(tree, else_cond);
}

pub fn visitLoop(self: *Self, tree: *const ast.Tree, span: common.Span, loop: ast.Loop, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    // Loop body.
    const loop_body = try self.metadata.pushScope();
    self.metadata.references[loop.body] = loop_body;
    try self.accept(tree, loop.body);
    _ = self.metadata.popScope();
}

pub fn visitWhileLoop(self: *Self, tree: *const ast.Tree, span: common.Span, loop: ast.WhileLoop, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    // Analyze condition before entering body.
    try self.accept(tree, loop.condition);

    // Loop body.
    const loop_body = try self.metadata.pushScope();
    self.metadata.references[loop.body] = loop_body;
    try self.accept(tree, loop.body);
    _ = self.metadata.popScope();
}

pub fn visitForLoop(self: *Self, tree: *const ast.Tree, span: common.Span, loop: ast.ForLoop, visitee: anytype) !void {
    _ = span;
    _ = visitee;

    // Analyze iterator before entering body.
    try self.accept(tree, loop.iterable);

    // Loop body.
    const loop_body = try self.metadata.pushScope();
    self.metadata.references[loop.body] = loop_body;
    // Bind binding.
    const scope = self.metadata.currentScope();
    const binding_name = tree.getNodeUnsafe(loop.binding).kind.identifier;
    try scope.known_names.put(binding_name, loop.binding);

    try self.accept(tree, loop.body);
    _ = self.metadata.popScope();
}
