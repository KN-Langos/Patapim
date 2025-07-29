const std = @import("std");

const reportz = @import("reportz");

const common = @import("../common.zig");
const ast = @import("../parse/ast.zig");
const intrinsics = @import("intrinsics.zig");
const runtime = @import("runtime.zig");

source_id: []const u8,
allocator: std.mem.Allocator,
tree: *const ast.Tree,
global_env: runtime.Environment,
mem_alloc_arena: std.heap.ArenaAllocator,

// Diagnostics for logging errors.
// These are untouched until the error occurs.
diagnostic_arena: std.heap.ArenaAllocator,
diagnostic_log: std.ArrayList(reportz.reports.Diagnostic),

pub const Self = @This();
const LOG = std.log.scoped(.interpreter);

pub const FlowControl = union(enum) {
    NOTHING,
    BREAK,
    CONTINUE,
    RETURN: runtime.RuntimeValue,
};

pub var flow_control: FlowControl = .NOTHING;

// Initializes the interpreter with the given AST tree and global environment.
// The global environment is used to store variables and their values.
pub fn init(allocator: std.mem.Allocator, tree: *const ast.Tree, source_id: []const u8) !Self {
    const global_environment = try runtime.Environment.init(allocator, null, true);

    return Self{
        .source_id = source_id,
        .allocator = allocator,
        .tree = tree,
        .global_env = global_environment,
        .diagnostic_arena = .init(allocator),
        .diagnostic_log = .init(allocator),
        .mem_alloc_arena = std.heap.ArenaAllocator.init(allocator),
    };
}

// Deinitializes the interpreter, freeing up resources.
// This includes deinitializing the global environment and diagnostic log.
// It should be called when the interpreter is no longer needed.
// It is important to call this to prevent memory leaks.
pub fn deinit(self: *Self) void {
    self.diagnostic_log.deinit();
    self.diagnostic_arena.deinit();
    self.global_env.deinit();
    self.mem_alloc_arena.deinit();
}

// Prints debug information about the interpreter's state.
// This includes the contents of the global environment, such as variable names and their values.
// It is useful for debugging purposes to see the current state of the interpreter.
pub fn printDebugInfo(self: *Self) !void {
    std.debug.print("\n\n---< Debug Info >---\n\n", .{});

    var it = self.global_env.values.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        // Optional: if `toString` allocates memory, remember to free it
        const value_str = try value.value.toString(self.allocator);
        std.debug.print("Entry: {s} = {s}\n", .{ key, value_str });
        self.allocator.free(value_str);
    }
}

// Error types used in the interpreter.
pub const Error = error{
    InvalidNodeId,
    UnsupportedNodeType,
    RuntimeError,
    InvalidTypeForBinaryOperation,
    DivisionByZero,
    WrongArgumentForSpread,
    IndexOutOfBounds,
    IndexNotAnInteger,
    NativeFunctionLoadError,
} || runtime.Error || std.DynLib.Error || std.mem.Allocator.Error;

// Reports an error with the given code, message format, and arguments.
// It appends the error to the diagnostic log and returns the specified error type.
pub fn reportError(
    self: *Self,
    code: []const u8,
    comptime message_fmt: []const u8,
    message_args: anytype,
    error_type: Self.Error,
    additional_options: struct {
        severity: reportz.reports.Severity = .@"error",
        labels: []const reportz.reports.Label,
        notes: []const reportz.reports.Note = &.{},
    },
) Self.Error {
    @branchHint(.cold);

    const diagnostic_alloc = self.diagnostic_arena.allocator();

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

// Interprets the AST tree starting from the root node.
// It evaluates the nodes in the tree and executes the corresponding actions.
// The global environment is used to store variable bindings and their values.
pub fn interpret(self: *Self, root_id: usize) !void {
    _ = try self.evalNode(self.tree, root_id, &self.global_env);
}

// Evaluates a node in the AST tree.
// It dispatches the evaluation to the appropriate handler based on the node type.
// The node can be a module, code block, expression, or variable declaration.
pub fn evalNode(self: *Self, tree: *const ast.Tree, node_id: usize, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    if (flow_control != .NOTHING) {
        if (flow_control == .RETURN) {
            return flow_control.RETURN;
        }

        return .Void;
    }

    const node = tree.getNode(node_id) orelse return self.reportError(
        "I001",
        "Node with ID {} does not exist.",
        .{node_id},
        error.InvalidNodeId,
        .{
            .labels = &.{.{
                .color = .{ .basic = .red },
                .span = (common.Span{ .start = node_id, .end = node_id + 1 }).asReportz(),
                .message = "Node ID out of bounds.",
            }},
        },
    );

    return switch (node.kind) {
        .module => |module| {
            // Evaluate the module, which is the root of the AST.
            var result: runtime.RuntimeValue = .Void;
            result = try self.evalNode(tree, module.body, env);
            return result;
        },
        .code_block => |code_block| {
            // Evaluate the code block, which is a sequence of statements.
            var result: runtime.RuntimeValue = .Void;
            var block_env = env;

            var heap_env: ?*runtime.Environment = null;
            if (!env.is_top_level) {
                heap_env = try self.allocator.create(runtime.Environment);
                heap_env.?.* = try runtime.Environment.init(self.allocator, env, false);
                block_env = heap_env.?;
            }
            env.is_top_level = false;

            defer if (heap_env) |e| {
                e.deinit();
                self.allocator.destroy(e);
            };

            for (code_block) |stmt_id| {
                result = try self.evalNode(tree, stmt_id, block_env);
            }
            return runtime.RuntimeValue.Void;
        },
        .array_literal => evalArrayLiteral(self, tree, node, env),
        .indexed_access => evalIndexedAccess(self, tree, node, env),
        .member_access => {
            const member_access = node.kind.member_access;
            // this was stolen from another function, it could need some changes TODO: extract to outer function
            const member = tree.getNode(member_access.member) orelse return self.reportError(
                "I001",
                "Node with ID {} does not exist.",
                .{node_id},
                error.InvalidNodeId,
                .{
                    .labels = &.{.{
                        .color = .{ .basic = .red },
                        .span = (common.Span{ .start = node_id, .end = node_id + 1 }).asReportz(),
                        .message = "Node ID out of bounds.",
                    }},
                },
            );
            const target = try self.evalNode(tree, member_access.target, env);
            env.this_context = target;
            if (target == .Array) {
                if (std.mem.eql(u8, member.kind.identifier, "len")) {
                    return runtime.RuntimeValue{ .Integer = @intCast(target.Array.items.len) };
                }
                if (std.mem.eql(u8, member.kind.identifier, "push")) {
                    return runtime.RuntimeValue{ .IntrinsicFunction = .{
                        .ptr = intrinsics.arrayPush,
                    } };
                }
            } else if (target == .Tuple and member.kind == .integer_literal) {
                if (member.kind.integer_literal > target.Tuple.len) {
                    return self.reportError(
                        "I013",
                        "Tuple index out of bounds: {d}.",
                        .{member.kind.integer_literal},
                        error.IndexOutOfBounds,
                        .{
                            .labels = &.{.{
                                .color = .{ .basic = .red },
                                .span = node.span.asReportz(),
                                .message = "Tuple index out of bounds.",
                            }},
                        },
                    );
                }

                return target.Tuple[member.kind.integer_literal];
            }

            // temporary solution
            return self.reportError(
                "I006",
                "Unsupported node type: {s}",
                .{@tagName(node.kind)},
                error.UnsupportedNodeType,
                .{
                    .labels = &.{.{
                        .color = .{ .basic = .red },
                        .span = node.span.asReportz(),
                        .message = "Unsupported node type.",
                    }},
                },
            );
        },
        .integer_literal => runtime.RuntimeValue{ .Integer = @intCast(node.kind.integer_literal) },
        .float_literal => runtime.RuntimeValue{ .Float = node.kind.float_literal },
        .boolean_literal => runtime.RuntimeValue{ .Boolean = node.kind.boolean_literal },
        .string_literal => runtime.RuntimeValue{ .String = node.kind.string_literal },
        .identifier => |identifier| {
            const value = env.get(identifier) orelse return self.reportError(
                "I002",
                "Identifier '{s}' not found in the current environment.",
                .{identifier},
                error.RuntimeError,
                .{
                    .labels = &.{.{
                        .color = .{ .basic = .red },
                        .span = node.span.asReportz(),
                        .message = "Identifier not found.",
                    }},
                },
            );
            return value;
        },
        .assignment => try self.evalAssignment(tree, node, env),
        .binary_operator => try self.evalBinaryExpr(tree, node, env),
        .unary_operator => try self.evalUnaryExpr(tree, node, env),
        .expression_group => |group| {
            // Evaluate the expression inside the group.
            return try self.evalNode(tree, group.expression, env);
        },
        .expr_stmt => |expr_stmt| {
            env.this_context = null; // Reset context of "this".
            // Evaluate the expression statement.
            return try self.evalNode(tree, expr_stmt, env);
        },
        .variable_ref => |variable_ref| {
            const name = try self.getIdentifierName(tree, variable_ref);

            // Evaluate the variable reference.
            const value = env.get(name) orelse return self.reportError(
                "I009",
                "Identifier '{s}' not found in the current environment.",
                .{name},
                error.RuntimeError,
                .{
                    .labels = &.{.{
                        .color = .{ .basic = .red },
                        .span = node.span.asReportz(),
                        .message = "Identifier not found.",
                    }},
                },
            );
            return value;
        },
        .tuple => |tuple| {
            const count = tuple.expressions.len;
            const elements = try self.mem_alloc_arena.allocator().alloc(runtime.RuntimeValue, count);

            for (tuple.expressions, 0..) |expr_id, i| {
                elements[i] = try self.evalNode(tree, expr_id, env);
            }

            return runtime.RuntimeValue{ .Tuple = elements };
        },
        .variable => |variable| {
            // Evaluate the variable declaration.
            const value = try self.evalNode(tree, variable.expression, env);

            const name = try self.getIdentifierName(tree, variable.name);

            try env.define(name, value, true);
            return value;
        },
        .constant => |constant| {
            // Evaluate the constant declaration.
            const value = try self.evalNode(tree, constant.expression, env);

            const name = try self.getIdentifierName(tree, constant.name);

            try env.define(name, value, false);
            return value;
        },
        .function_def => |function_def| {
            // Evaluate the function definition.
            const func_name = try self.getIdentifierName(tree, function_def.name);

            const param_names = try self.mem_alloc_arena.allocator().alloc([]const u8, function_def.parameters.len);
            for (function_def.parameters, 0..) |param, i| {
                const param_node = tree.getNode(param).?;
                const name = try self.getIdentifierName(tree, param_node.kind.parameter.name);
                param_names[i] = name;
            }

            // Create a new function value.
            const function_value = runtime.FunctionValue{
                .parameters = param_names,
                .body_id = function_def.body,
                .environment = env,
            };

            // Define the function in the environment.
            try env.define(func_name, .{ .Function = function_value }, true);
            return .{ .Function = function_value };
        },
        .native_function_decl => self.evalNativeFunctionDeclaration(tree, node, env),
        .function_call => return try self.evalFunctionCall(tree, node, env),
        .conditional => return try self.evalConditional(tree, node, env),
        .loop => return try self.evalLoop(tree, node, env),
        .while_loop => return try self.evalWhile(tree, node, env),
        .break_stmt => {
            flow_control = .BREAK;
            return runtime.RuntimeValue.Void;
        },
        .continue_stmt => {
            flow_control = .CONTINUE;
            return runtime.RuntimeValue.Void;
        },
        .return_stmt => |returnStmt| {
            if (returnStmt.value == null) {
                flow_control = .{ .RETURN = runtime.RuntimeValue.Void };
            } else {
                const return_value = try self.evalNode(tree, returnStmt.value.?, env);
                flow_control = .{ .RETURN = return_value };
            }

            return flow_control.RETURN;
        },
        .inline_conditional => return try self.evalInlineConditional(tree, node, env),
        .struct_decl => return try self.evalStructDeclaration(tree, node, env),
        .struct_literal => |struct_literal| {
            _ = struct_literal;

            return runtime.RuntimeValue.Void;
        },
        else => {
            LOG.warn("Unsupported node type: {s}", .{@tagName(node.kind)});

            return self.reportError(
                "I006",
                "Unsupported node type: {s}",
                .{@tagName(node.kind)},
                error.UnsupportedNodeType,
                .{
                    .labels = &.{.{
                        .color = .{ .basic = .red },
                        .span = node.span.asReportz(),
                        .message = "Unsupported node type.",
                    }},
                },
            );
        },
    };
}

pub fn evalAssignment(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) !runtime.RuntimeValue {
    const assignment = node.kind.assignment;
    const name_node = tree.getNode(assignment.target) orelse return self.reportError(
        "I010",
        "Node with ID {} does not exist.",
        .{assignment.target},
        error.InvalidNodeId,
        .{
            .labels = &.{.{
                .color = .{ .basic = .red },
                .span = node.span.asReportz(),
                .message = "Node ID out of bounds.",
            }},
        },
    );

    const value = try self.evalNode(tree, assignment.value, env);

    const name = switch (name_node.kind) {
        .identifier => try self.getIdentifierName(tree, assignment.target),
        .variable_ref => try self.getIdentifierName(tree, name_node.kind.variable_ref),
        .indexed_access => {
            const index = try evalNode(self, tree, name_node.kind.indexed_access.index, env);
            const array = try evalNode(self, tree, name_node.kind.indexed_access.target, env);

            //implement error handling
            if (index != .Integer) {
                return self.reportError(
                    "I012",
                    "Index not an integer, found instead {s}.",
                    .{@tagName(index)},
                    error.IndexNotAnInteger,
                    .{
                        .labels = &.{.{
                            .color = .{ .basic = .red },
                            .span = node.span.asReportz(),
                            .message = "must use Integer as index",
                        }},
                    },
                );
            }

            if (index.Integer < 0 or index.Integer > array.Array.items.len) {
                return self.reportError(
                    "I011",
                    "Index out of bounds {d}.",
                    .{index.Integer},
                    error.IndexOutOfBounds,
                    .{
                        .labels = &.{.{
                            .color = .{ .basic = .red },
                            .span = node.span.asReportz(),
                            .message = "Node index out of bounds.",
                        }},
                    },
                );
            }
            const array_index: usize = @intCast(index.Integer);

            array.Array.items[array_index] = value;
            // break early to skip changes in environment
            return value;
        },
        else => return error.UnsupportedNodeType,
    };

    try env.set(name, value);

    // Return the assigned value.
    return value;
}

pub fn evalBinaryExpr(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) !runtime.RuntimeValue {
    const binary_expr = node.kind.binary_operator;
    const left_value = try self.evalNode(tree, binary_expr.left, env);
    const right_value = try self.evalNode(tree, binary_expr.right, env);

    return switch (binary_expr.operator) {
        .ADD => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Integer = li + ri },
                    .Float => |rf| break :blk .{ .Float = @as(f64, @floatFromInt(li)) + rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Float = lf + @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Float = lf + rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                // TODO: Implement string concatenation.
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .SUBTRACT => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Integer = li - ri },
                    .Float => |rf| break :blk .{ .Float = @as(f64, @floatFromInt(li)) - rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Float = lf - @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Float = lf - rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .MULTIPLY => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Integer = li * ri },
                    .Float => |rf| break :blk .{ .Float = @as(f64, @floatFromInt(li)) * rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Float = lf * @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Float = lf * rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .DIVIDE => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| if (ri == 0) return error.DivisionByZero else break :blk .{ .Integer = @divTrunc(li, ri) },
                    .Float => |rf| if (rf == 0.0) return error.DivisionByZero else break :blk .{ .Float = @divTrunc(@as(f64, @floatFromInt(li)), rf) },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| if (ri == 0) return error.DivisionByZero else break :blk .{ .Float = @divTrunc(lf, @as(f64, @floatFromInt(ri))) },
                    .Float => |rf| if (rf == 0.0) return error.DivisionByZero else break :blk .{ .Float = @divTrunc(lf, rf) },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .MODULO => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| if (ri == 0) return error.DivisionByZero else break :blk .{ .Integer = @rem(li, ri) },
                    .Float => |rf| if (rf == 0.0) return error.DivisionByZero else break :blk .{ .Float = @rem(@as(f64, @floatFromInt(li)), rf) },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| if (ri == 0) return error.DivisionByZero else break :blk .{ .Float = @rem(lf, @as(f64, @floatFromInt(ri))) },
                    .Float => |rf| if (rf == 0.0) return error.DivisionByZero else break :blk .{ .Float = @rem(lf, rf) },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .EQ_EQ => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = li == ri },
                    .Float => |rf| break :blk .{ .Boolean = @as(f64, @floatFromInt(li)) == rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = lf == @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Boolean = lf == rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Boolean => |lb| switch (right_value) {
                    .Boolean => |rb| break :blk .{ .Boolean = lb == rb },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .String => |ls| switch (right_value) {
                    .String => |rs| break :blk .{ .Boolean = std.mem.eql(u8, ls, rs) },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .NOT_EQ => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = li != ri },
                    .Float => |rf| break :blk .{ .Boolean = @as(f64, @floatFromInt(li)) != rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = lf != @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Boolean = lf != rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Boolean => |lb| switch (right_value) {
                    .Boolean => |rb| break :blk .{ .Boolean = lb != rb },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .String => |ls| switch (right_value) {
                    .String => |rs| break :blk .{ .Boolean = !std.mem.eql(u8, ls, rs) },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .LESS_THAN => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = li < ri },
                    .Float => |rf| break :blk .{ .Boolean = @as(f64, @floatFromInt(li)) < rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = lf < @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Boolean = lf < rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .GREATER_THAN => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = li > ri },
                    .Float => |rf| break :blk .{ .Boolean = @as(f64, @floatFromInt(li)) > rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = lf > @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Boolean = lf > rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .LESS_EQUAL => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = li <= ri },
                    .Float => |rf| break :blk .{ .Boolean = @as(f64, @floatFromInt(li)) <= rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = lf <= @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Boolean = lf <= rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .GREATER_EQUAL => blk: {
            switch (left_value) {
                .Integer => |li| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = li >= ri },
                    .Float => |rf| break :blk .{ .Boolean = @as(f64, @floatFromInt(li)) >= rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                .Float => |lf| switch (right_value) {
                    .Integer => |ri| break :blk .{ .Boolean = lf >= @as(f64, @floatFromInt(ri)) },
                    .Float => |rf| break :blk .{ .Boolean = lf >= rf },
                    else => return error.InvalidTypeForBinaryOperation,
                },
                else => return error.InvalidTypeForBinaryOperation,
            }
        },
        .LOGICAL_AND => blk: {
            const left_bool = switch (left_value) {
                .Boolean => |b| b,
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_bool = switch (right_value) {
                .Boolean => |b| b,
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Boolean = left_bool and right_bool };
        },
        .LOGICAL_OR => blk: {
            const left_bool = switch (left_value) {
                .Boolean => |b| b,
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_bool = switch (right_value) {
                .Boolean => |b| b,
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Boolean = left_bool or right_bool };
        },
        .BITSHIFT_LEFT => blk: {
            const left_int = switch (left_value) {
                .Integer => |i| i,
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_int = switch (right_value) {
                .Integer => |i| i,
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = left_int << @as(u6, @intCast(right_int)) };
        },
        .BITSHIFT_RIGHT => blk: {
            const left_int = switch (left_value) {
                .Integer => |i| i,
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_int = switch (right_value) {
                .Integer => |i| i,
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = left_int >> @as(u6, @intCast(right_int)) };
        },
        .BITWISE_AND => blk: {
            const left_val = switch (left_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_val = switch (right_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = left_val & right_val };
        },
        .BITWISE_OR => blk: {
            const left_val = switch (left_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_val = switch (right_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = left_val | right_val };
        },
        .BITWISE_XOR => blk: {
            const left_val = switch (left_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            const right_val = switch (right_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = left_val ^ right_val };
        },
        // RANGE: This is a placeholder for range operator.
        else => return self.reportError(
            "I004",
            "Unsupported binary operator: {s}",
            .{@tagName(binary_expr.operator)},
            error.UnsupportedNodeType,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .red },
                    .span = node.span.asReportz(),
                    .message = "Unsupported binary operator.",
                }},
            },
        ),
    };
}

pub fn evalUnaryExpr(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) !runtime.RuntimeValue {
    const unary_expr = node.kind.unary_operator;
    const operand_value = try self.evalNode(tree, unary_expr.operand, env);

    return switch (unary_expr.operator) {
        .NOT => blk: {
            const operand_bool = switch (operand_value) {
                .Boolean => |b| b,
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Boolean = !operand_bool };
        },
        .BITWISE_NOT => blk: {
            const operand_int = switch (operand_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = ~operand_int };
        },
        .SUBTRACT => blk: {
            const operand_int = switch (operand_value) {
                .Integer => |i| i,
                .Float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidTypeForBinaryOperation,
            };
            break :blk .{ .Integer = -operand_int };
        },
        // INCREMENT: This is a placeholder for increment operator.
        // DECREMENT: This is a placeholder for decrement operator.
        else => return self.reportError(
            "I005",
            "Unsupported unary operator: {s}",
            .{@tagName(unary_expr.operator)},
            error.UnsupportedNodeType,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .red },
                    .span = node.span.asReportz(),
                    .message = "Unsupported unary operator.",
                }},
            },
        ),
    };
}

// Evaluates a struct declaration.
pub fn evalStructDeclaration(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const struct_decl = node.kind.struct_decl;

    const struct_name = try self.getIdentifierName(tree, struct_decl.name);

    // Structure that stores fields names init
    const field_names = try self.mem_alloc_arena.allocator().alloc([]const u8, struct_decl.fields.len);

    for (struct_decl.fields, 0..) |field_id, i| {
        const field_name = try self.getIdentifierName(tree, field_id);
        field_names[i] = field_name;
    }

    var functions = std.StringHashMap(runtime.FunctionValue).init(self.mem_alloc_arena.allocator());
    const struct_env = try self.mem_alloc_arena.allocator().create(runtime.Environment);
    struct_env.* = try runtime.Environment.init(self.allocator, env, false);

    for (struct_decl.decls) |decl_id| {
        const decl_node = ((tree.getNode(decl_id)).?).kind.function_def;

        const func_name = try self.getIdentifierName(tree, decl_node.name);

        const param_names = try self.mem_alloc_arena.allocator().alloc([]const u8, decl_node.parameters.len);
        for (decl_node.parameters, 0..) |param, i| {
            const param_node = tree.getNode(param).?;
            const name = try self.getIdentifierName(tree, param_node.kind.parameter.name);
            param_names[i] = name;
        }

        // Create a new function value.
        const function_value = runtime.FunctionValue{
            .parameters = param_names,
            .body_id = decl_node.body,
            .environment = struct_env,
        };

        try functions.put(func_name, function_value);
    }

    // Create a new struct value.
    const struct_value = runtime.StructType{
        .name = struct_name,
        .fields = field_names,
        .methods = functions,
        .environment = struct_env,
    };

    try env.declareType(struct_name, struct_value);

    return runtime.RuntimeValue.Void;
}

// Evaluates a native function declaration.
// It loads the native function from a shared library and registers it in the environment.
pub fn evalNativeFunctionDeclaration(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const native_function_decl = node.kind.native_function_decl;

    // Evaluate the native function declaration.
    const func_name = try self.getIdentifierName(tree, native_function_decl.name);
    const parsed_abi = try parseAbiString(tree, native_function_decl.abi.?);

    var library = try std.DynLib.open(parsed_abi.lib);

    const symbol_name = if (parsed_abi.sym) |sym| sym else func_name;

    const symbol_name_with_null = try std.mem.concat(self.allocator, u8, &[_][]const u8{ symbol_name, "\x00" });
    defer self.allocator.free(symbol_name_with_null);

    const fn_ptr = library.lookup(*const fn (*const runtime.RuntimeValue, usize, *runtime.RuntimeValue) callconv(.C) void, symbol_name_with_null[0 .. symbol_name_with_null.len - 1 :0]) orelse return self.reportError(
        "I017",
        "Failed to load native function '{s}' from library '{s}'.",
        .{ symbol_name, parsed_abi.lib },
        error.NativeFunctionLoadError,
        .{
            .labels = &.{.{
                .color = .{ .basic = .red },
                .span = node.span.asReportz(),
                .message = "Failed to load native function.",
            }},
        },
    );

    const params = try self.mem_alloc_arena.allocator().alloc(runtime.NativeFunctionValue.Arg, native_function_decl.parameters.len);
    for (native_function_decl.parameters, 0..) |param, i| {
        const param_node = tree.getNode(param).?;
        const name = try self.getIdentifierName(tree, param_node.kind.native_parameter.name);
        params[i] = .{ .name = name, .type = param_node.kind.native_parameter.type };
    }

    const native_function_value = runtime.NativeFunctionValue{
        .name = func_name,
        .parameters = params,
        .fn_ptr = fn_ptr,
    };

    const fn_key = try std.fmt.allocPrint(self.mem_alloc_arena.allocator(), "{s}/{}", .{ func_name, native_function_decl.parameters.len });

    try env.define(fn_key, .{ .NativeFunction = native_function_value }, false);
    return .{ .NativeFunction = native_function_value };
}

pub fn evalFunctionCall(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const func_call = node.kind.function_call;
    const func_value = try self.evalNode(tree, func_call.target, env);

    switch (func_value) {
        .Function => |fun| {
            var func_env = try runtime.Environment.init(self.allocator, func_value.Function.environment, false);
            defer func_env.deinit();

            for (fun.parameters, 0..) |param_name, i| {
                const arg = try self.evalNode(tree, func_call.arguments[i], env);
                try func_env.define(param_name, arg, true);
            }
            if (env.this_context) |this|
                try func_env.define("this", this, false);

            _ = try self.evalNode(tree, func_value.Function.body_id, &func_env);
        },

        .IntrinsicFunction => |fun| {
            var args = try self.allocator.alloc(runtime.RuntimeValue, func_call.arguments.len);
            defer self.allocator.free(args);

            for (0..func_call.arguments.len) |i| {
                const arg = try self.evalNode(tree, func_call.arguments[i], env);
                args[i] = arg;
            }

            flow_control = .{ .RETURN = try fun.ptr(env.this_context, args, env) };
        },

        .NativeFunction => |native_fn| {
            // Prepare the arguments for the native function.
            const args = try self.allocator.alloc(runtime.RuntimeValue, func_call.arguments.len);
            defer self.allocator.free(args);

            if (func_call.arguments.len != native_fn.parameters.len) {
                return self.reportError(
                    "I014",
                    "Native function expects {d} arguments, but got {d}.",
                    .{ native_fn.parameters.len, func_call.arguments.len }, // TODO: Provide nice name.
                    error.RuntimeError,
                    .{
                        .labels = &.{.{
                            .color = .{ .basic = .red },
                            .span = node.span.asReportz(),
                            .message = "Argument count mismatch.",
                        }},
                    },
                );
            }

            for (func_call.arguments, 0..) |arg_id, i| {
                args[i] = try self.evalNode(tree, arg_id, env);
                const runtime_type: ast.Type = switch (args[i]) {
                    .Integer => .Int,
                    .Float => .Float,
                    .String => .String,
                    .Boolean => .Bool,
                    .Array => .Array,
                    .Function => .Function,
                    .NativeFunction => .Function,
                    .IntrinsicFunction => .Function,
                    .Tuple => .Tuple,
                    .Void => .Unknown,
                };

                if (native_fn.parameters[i].type != .Unknown and native_fn.parameters[i].type != runtime_type) {
                    return self.reportError(
                        "I015",
                        "Native function parameter {d} expects type {s}, but got {s}.",
                        .{ i, @tagName(native_fn.parameters[i].type), @tagName(runtime_type) },
                        error.RuntimeError,
                        .{
                            .labels = &.{.{
                                .color = .{ .basic = .red },
                                .span = node.span.asReportz(),
                                .message = "Argument type mismatch.",
                            }},
                        },
                    );
                }
            }

            // Call the native function.
            var result: runtime.RuntimeValue = runtime.RuntimeValue.Void;
            native_fn.fn_ptr(&args[0], args.len, &result);
            flow_control = .{ .RETURN = result };
        },

        else => return self.reportError(
            "I014",
            "Called value is not a function or intrinsic.",
            .{},
            error.RuntimeError,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .red },
                    .span = node.span.asReportz(),
                    .message = "This is not callable.",
                }},
            },
        ),
    }

    defer flow_control = .NOTHING;

    const return_value = if (flow_control == .RETURN) flow_control.RETURN else runtime.RuntimeValue.Void;
    env.this_context = return_value;
    return return_value;
}

pub fn evalConditional(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const conditional = node.kind.conditional;

    // If there's no condition, it's an unconditional else block.
    if (conditional.condition == null) {
        return try self.evalNode(tree, conditional.body, env);
    }

    // Evaluate the condition expression.
    const condition_value = try self.evalNode(tree, conditional.condition.?, env);
    const condition_bool = isTruthy(condition_value);

    // If the condition is true, evaluate the 'then' block.
    if (condition_bool) {
        return try self.evalNode(tree, conditional.body, env);
    } else if (conditional.else_conditional != null) {
        // If there is an 'else' block, evaluate it.
        return try self.evalNode(tree, conditional.else_conditional.?, env);
    }

    // If there is no 'else if' or 'else' block, return Void.
    return runtime.RuntimeValue.Void;
}

pub fn checkBreak() bool {
    if (flow_control == .BREAK) {
        flow_control = .NOTHING;
        return true;
    } else {
        flow_control = .NOTHING;
        return false;
    }
}

pub fn evalLoop(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const loop = node.kind.loop;

    var return_value: runtime.RuntimeValue = runtime.RuntimeValue.Void;

    while (true) {
        if (checkBreak())
            break;

        return_value = try self.evalNode(tree, loop.body, env);
    }
    return return_value;
}

pub fn evalWhile(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const while_loop = node.kind.while_loop;

    var condition_value = try self.evalNode(tree, while_loop.condition, env);
    var condition_bool = isTruthy(condition_value);
    var return_value: runtime.RuntimeValue = runtime.RuntimeValue.Void;

    while (condition_bool) {
        if (checkBreak())
            break;

        return_value = try self.evalNode(tree, while_loop.body, env);

        condition_value = try self.evalNode(tree, while_loop.condition, env);
        condition_bool = isTruthy(condition_value);
    }

    return return_value;
}

pub fn evalInlineConditional(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const inline_conditional = node.kind.inline_conditional;

    // Evaluate the condition expression.
    const condition_value = try self.evalNode(tree, inline_conditional.condition, env);
    const condition_bool = isTruthy(condition_value);

    // If the condition is true, evaluate the 'then' expression.
    if (condition_bool) {
        return try self.evalNode(tree, inline_conditional.then_expr, env);
    }

    // If the condition is false, evaluate the 'else' expression.
    return try self.evalNode(tree, inline_conditional.else_expr, env);
}

// Checks if a runtime value is truthy.
// This function is used to determine the truthiness of a value in conditional expressions.
// It returns true for non-zero integers, non-zero floats, non-empty strings, and true boolean values.
// All other values are considered falsey.
fn isTruthy(value: runtime.RuntimeValue) bool {
    return switch (value) {
        .Boolean => |b| b,
        .Integer => |i| i != 0,
        .Float => |f| f != 0.0,
        .String => |s| s.len != 0,
        .Array => |a| a.items.len != 0,
        else => false, // Other types are considered falsey.
    };
}

// Gets the identifier name from the AST tree for a given node ID.
// This function retrieves the identifier node and checks if it is of the correct type.
fn getIdentifierName(self: *Self, tree: *const ast.Tree, node_id: usize) Self.Error![]const u8 {
    const identifier_node = tree.getNode(node_id) orelse return self.reportError(
        "I007",
        "Identifier with ID {} does not exist.",
        .{node_id},
        error.InvalidNodeId,
        .{
            .labels = &.{.{
                .color = .{ .basic = .red },
                .span = (common.Span{ .start = node_id, .end = node_id + 1 }).asReportz(),
                .message = "Variable name ID out of bounds.",
            }},
        },
    );

    const identifier = switch (identifier_node.kind) {
        .identifier => identifier_node.kind.identifier,
        else => return self.reportError(
            "I008",
            "Name must be an identifier, found: {s}",
            .{@tagName(identifier_node.kind)},
            error.UnsupportedNodeType,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .red },
                    .span = identifier_node.span.asReportz(),
                    .message = "Invalid name.",
                }},
            },
        ),
    };

    return identifier;
}

// must be used on floats or ints only
fn addOne(value: runtime.RuntimeValue) runtime.RuntimeValue {
    var return_val: runtime.RuntimeValue = value;

    switch (value) {
        .Float => |val| {
            return_val = runtime.RuntimeValue{ .Float = val + 1.0 };
        },
        .Integer => |val| {
            return_val = runtime.RuntimeValue{ .Integer = val + 1 };
        },
        else => unreachable,
    }
    return return_val;
}

//helper function for spreads in arrays maybe to be reimplemented or deleted in future
fn compare(self: *Self, t1: runtime.RuntimeValue, t2: runtime.RuntimeValue) Self.Error!isize {
    const Tag = std.meta.Tag(runtime.RuntimeValue);
    const tag1 = @as(Tag, t1);
    const tag2 = @as(Tag, t2);

    if (tag1 != tag2) {
        return self.reportError("I010", "Spread must contain two values of the same type: {s}, {s}", .{ @tagName(tag1), @tagName(tag2) }, error.WrongArgumentForSpread, .{ .labels = &.{.{
            .color = .{ .basic = .red },
            .span = .{ .start = 0, .end = 1 },
            .message = "Invalid type",
        }} });
    }

    return switch (t1) {
        .Float => |val1| {
            const val2 = t2.Float;
            return if (val1 == val2) 0 else if (val1 > val2) 1 else -1;
        },
        .Integer => |val1| {
            const val2 = t2.Integer;
            return if (val1 == val2) 0 else if (val1 > val2) 1 else -1;
        },
        else => self.reportError("I009", "Spread must be made of numeric types, found instead {s}", .{@tagName(tag1)}, error.WrongArgumentForSpread, .{ .labels = &.{.{
            .color = .{ .basic = .red },
            .span = .{ .start = 0, .end = 1 },
            .message = "Invalid type.",
        }} }),
    };
}

pub fn evalArrayLiteral(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const array_literal = node.kind.array_literal;

    const alloc = env.arena_allocator.allocator();
    var return_array = try alloc.create(std.ArrayList(runtime.RuntimeValue));
    errdefer alloc.destroy(return_array);
    return_array.* = .init(env.arena_allocator.allocator());
    errdefer return_array.deinit();

    for (array_literal.elements) |element| {
        try return_array.append(try evalNode(self, tree, element, env));
    }

    if (array_literal.spread == null) {
        return runtime.RuntimeValue{
            .Array = return_array,
        };
    }

    return self.reportError(
        "I006",
        "Unsupported node type: {s}",
        .{@tagName(node.kind)},
        error.UnsupportedNodeType,
        .{
            .labels = &.{.{
                .color = .{ .basic = .red },
                .span = node.span.asReportz(),
                .message = "Unsupported node type.",
            }},
        },
    );
}

pub fn evalIndexedAccess(self: *Self, tree: *const ast.Tree, node: ast.Node, env: *runtime.Environment) Self.Error!runtime.RuntimeValue {
    const index_access = node.kind.indexed_access;
    const index = try evalNode(self, tree, index_access.index, env);
    const target = try evalNode(self, tree, index_access.target, env);

    if (index != .Integer) {
        return self.reportError(
            "I012",
            "Index not an integer, found instead {s}.",
            .{@tagName(index)},
            error.IndexNotAnInteger,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .red },
                    .span = node.span.asReportz(),
                    .message = "must use Integer as index",
                }},
            },
        );
    }

    if (index.Integer < 0 or index.Integer > target.Array.items.len) {
        return self.reportError(
            "I011",
            "Index out of bounds {d}.",
            .{index.Integer},
            error.IndexOutOfBounds,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .red },
                    .span = node.span.asReportz(),
                    .message = "Node index out of bounds.",
                }},
            },
        );
    }

    const usize_index: usize = @intCast(index.Integer);

    const value = target.Array.items[usize_index];
    env.this_context = value;
    return value;
}

const AbiParts = struct {
    lib: []const u8,
    sym: ?[]const u8,
};

fn parseAbiString(tree: *const ast.Tree, abi: usize) Self.Error!AbiParts {
    const abi_node = tree.getNode(abi) orelse return error.InvalidNodeId;

    const abi_str = switch (abi_node.kind) {
        .string_literal => |s| s,
        else => return error.UnsupportedNodeType,
    };

    const last_slash = std.mem.lastIndexOfScalar(u8, abi_str, '/');
    const last_dot = std.mem.lastIndexOfScalar(u8, abi_str, '.');

    // Check if it's in form of path/to/lib.so/symbol
    if (last_slash) |i| {
        if (last_dot) |dot| {
            if (dot < i) {
                const lib = abi_str[0..i];
                const sym = abi_str[i + 1 ..];
                return AbiParts{ .lib = lib, .sym = sym };
            }
        }
    }

    // fallback: path is just a library with no symbol
    return AbiParts{ .lib = abi_str, .sym = null };
}
