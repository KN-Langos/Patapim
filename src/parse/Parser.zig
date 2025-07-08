const std = @import("std");

const reportz = @import("reportz");

const common = @import("../common.zig");
const Lexer = @import("../Lexer.zig");
const Token = Lexer.Token;
const TokenType = Lexer.TokenType;
const ast = @import("ast.zig");

allocator: std.mem.Allocator,
tree: ast.Tree,

// Parser references lexer, because it does not allocate,
// so we parse tokens one by one.
lexer: *Lexer,

// Diagnostics for logging errors.
// These are untouched until the error occurs.
diagnostic_arena: std.heap.ArenaAllocator,
diagnostic_log: std.ArrayList(reportz.reports.Diagnostic),

// ---< Internal fields begin >---
cached_token: ?Token = null,
last_token: ?Token = null,
span_stack: std.ArrayList(usize),
// ---< Internal fields end >---

const Self = @This();
const LOG = std.log.scoped(.parser);

pub const Error = error{
    UnexpectedToken,
    ExpectedStatement,
    NodeNotFound,
    ExpectedExpressionAtom,
} || Lexer.Error || std.mem.Allocator.Error;

pub fn init(alloc: std.mem.Allocator, lexer: *Lexer) Self {
    return Self{
        .allocator = alloc,
        .tree = .init(alloc),
        .lexer = lexer,
        .diagnostic_arena = .init(alloc),
        .diagnostic_log = .init(alloc),

        .span_stack = .init(alloc),
    };
}

pub fn deinit(self: *Self, deinit_tree: bool) void {
    if (deinit_tree) // We may want to keep the tree for further passes or interpreter.
        self.tree.deinit();
    self.diagnostic_log.deinit();
    self.diagnostic_arena.deinit();
    self.span_stack.deinit();
}

// ---< Helper and utility functions begin >---

// Internal method for reporting error diagnostics.
// This should be called in place of `error.*` whenever returning any errors.
// Please examine the code below to get more details on usage before implementing new features.
fn reportError(
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
    // This tells the compiler this function is unlikely to be called.
    @branchHint(.cold);

    const diagnostic_alloc = self.diagnostic_arena.allocator();

    try self.diagnostic_log.append(reportz.reports.Diagnostic{
        .source_id = self.lexer.source_id,
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

// Peek at the next token without advancing.
fn peek(self: *Self) !Token {
    if (self.cached_token) |cached|
        return cached;
    self.cached_token = try self.lexer.next(self.tree.allocator());
    return self.cached_token.?; // We may do `.?` because we set it above.
}

// Advance one token forward and return current token.
fn advance(self: *Self) !Token {
    const current_token = try self.peek();
    self.last_token = current_token;
    self.cached_token = null;
    return current_token;
}

// Advance parser by one token and expect token to be of given type.
// If token type does not match, this function will return an error.
// If token type matches, this function will return the token.
fn expect(self: *Self, expected_type: TokenType) Self.Error!Token {
    if ((try self.peek()).type == expected_type)
        return try self.advance()
    else {
        @branchHint(.unlikely);
        const invalid_token = try self.advance();
        // TODO: Make some kind of map to report expected tokens in a more pretty way.
        return self.reportError(
            "P001",
            "Found invalid token. Expected '{any}' but got '{s}'.",
            .{ expected_type, invalid_token.lexeme },
            error.InvalidToken,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .magenta },
                    .span = .{ .start = invalid_token.span.start, .end = invalid_token.span.end },
                    .message = "Found this token.",
                }},
            },
        );
    }
}

// Works similarly to `expect` method, but instead of panicking
// if the token does not match it just returns null.
fn maybe(self: *Self, maybe_type: TokenType) Self.Error!?Token {
    return if ((try self.peek()).type == maybe_type)
        try self.advance()
    else
        null;
}

// Push new span beginning to the stack.
// Due to implementation details this function should be called
// **AFTER** parsing first element in a span.
fn pushSpan(self: *Self) std.mem.Allocator.Error!void {
    try self.span_stack.append(self.last_token.?.span.start);
}

// Push new span beginning to the stack.
// Opposed to `pushSpan` method, this one uses next token
// instead of last token.
fn pushSpanOnNextToken(self: *Self) Self.Error!void {
    const next_token = try self.peek();
    try self.span_stack.append(next_token.span.start);
}

// Get current span from the stack.
// This function assumes that stack is not empty.
fn popSpan(self: *Self) common.Span {
    const span_start = self.span_stack.pop().?;
    const span_end = self.last_token.?.span.end;
    return .{ .start = span_start, .end = span_end };
}

// Get current span from the stack without popping it.
fn peekSpan(self: *Self) common.Span {
    const span_start = self.span_stack.getLast();
    const span_end = self.last_token.?.span.end;
    return .{ .start = span_start, .end = span_end };
}

fn expectIdentifier(self: *Self) !usize {
    const ident = try self.expect(.IDENTIFIER);
    return self.tree.addNode(.{
        .span = ident.span,
        .kind = .{ .identifier = ident.lexeme },
    });
}

// ---< Helper and utility functions end >---

// Parse whole source returning main "module" node.
pub fn parseWholeSource(self: *Self) !usize {
    var module_statements = std.ArrayList(usize).init(self.tree.allocator());
    errdefer module_statements.deinit(); // This function may fail early.

    try self.pushSpanOnNextToken();
    defer _ = self.popSpan(); // We do not need to keep this span on stack after error.

    while (!self.lexer.isAtEnd()) {
        const stmt = try self.parseAnyStatement();
        try module_statements.append(stmt);
    }

    const body = try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .code_block = try module_statements.toOwnedSlice() },
    });
    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .module = .{ .body = body } },
    });
}

// Parse any statement and return its ID.
// This function fails if no statement is possible to parse,
// so ensure there is no EOF before calling this.
pub fn parseAnyStatement(self: *Self) Self.Error!usize {
    try self.pushSpanOnNextToken();
    defer _ = self.popSpan(); // We need span only in case of an error.

    if (try self.parseMaybeImportStatement()) |stmt| return stmt;
    if (try self.parseMaybeFunctionDefStatement()) |stmt| return stmt;
    if (try self.parseMaybeNativeFunctionDeclStatement()) |stmt| return stmt;
    if (try self.parseMaybeVariableDeclaration()) |stmt| return stmt;
    if (try self.parseMaybeConstantDeclaration()) |stmt| return stmt;
    if (try self.parseMaybeCallOrAccess()) |stmt| return stmt;

    // If nothing has returned up to this point, we assume that there
    // is no statement where it should be and panic.
    return self.reportError(
        "P002",
        "Expected statement, but found something else.",
        .{},
        error.ExpectedStatement,
        .{
            .labels = &.{.{
                .color = .{ .basic = .magenta },
                .span = self.peekSpan().asReportz(),
                .message = "Found this instead.",
            }},
        },
    );
}

//parse variable declaration statement and return its ID if parsed.
// For more information please reference `ast.zig -> Variable` struct.
pub fn parseMaybeVariableDeclaration(self: *Self) !?usize {
    if (try self.maybe(.KW_VARIABLE) == null) return null;
    try self.pushSpan();
    defer _ = self.popSpan();
    const var_name = try self.expectIdentifier();
    _ = try self.expect(.ASSIGN);
    const expression = try self.parseExpression();
    _ = try self.expect(.SEMICOLON);
    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .variable = .{
            .name = var_name,
            .expression = expression,
        } },
    });
}

// parse constant declaration statement and return its ID if parsed.
// For more information please reference `ast.zig -> Const` struct.
pub fn parseMaybeConstantDeclaration(self: *Self) !?usize {
    if (try self.maybe(.KW_CONST) == null) return null;
    try self.pushSpan();
    defer _ = self.popSpan();
    const const_name = try self.expectIdentifier();
    _ = try self.expect(.ASSIGN);
    const expression = try self.parseExpression();
    _ = try self.expect(.SEMICOLON);
    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .constant = .{
            .name = const_name,
            .expression = expression,
        } },
    });
}

// Parse import statement and return its ID if parsed.
// For more information please reference `ast.zig -> Import` struct.
pub fn parseMaybeImportStatement(self: *Self) !?usize {
    if (try self.maybe(.KW_IMPORT) == null) return null; // This may not be an import statement.
    try self.pushSpan();
    defer _ = self.popSpan();
    const source_path = try self.expect(.STRING_LITERAL);
    const source_path_node = try self.tree.addNode(.{
        .span = source_path.span,
        .kind = .{ .string_literal = source_path.literal.string },
    });
    if (try self.maybe(.KW_AS) != null) {
        const import_rename_node = try self.expectIdentifier();
        _ = try self.expect(.SEMICOLON);
        return try self.tree.addNode(.{
            .span = self.peekSpan(),
            .kind = .{ .import = .{
                .source = source_path_node,
                .opt_rename = import_rename_node,
            } },
        });
    } else {
        _ = try self.expect(.SEMICOLON);
        return try self.tree.addNode(.{
            .span = self.peekSpan(),
            .kind = .{ .import = .{
                .source = source_path_node,
            } },
        });
    }
}

// Parse function definition statement and return its ID if parsed.
// For more information please reference `ast.zig -> FunctionDef` struct.
pub fn parseMaybeFunctionDefStatement(self: *Self) !?usize {
    if (try self.maybe(.KW_FUNCTION) == null) return null; // This may not be a fn statement.
    try self.pushSpan();
    defer _ = self.popSpan();
    const fn_name = try self.expectIdentifier();
    _ = try self.expect(.LEFT_PAREN);

    var fn_parameters = std.ArrayList(usize).init(self.tree.allocator());
    errdefer fn_parameters.deinit(); // This may fail early.

    while (try self.maybe(.RIGHT_PAREN) == null) {
        // This may be moved to a separate function,
        // but I do not see any other place parameters are used.
        const param_name = try self.expectIdentifier();
        try self.pushSpan();
        defer _ = self.popSpan();

        const param = try self.tree.addNode(.{
            .span = self.peekSpan(),
            .kind = .{ .parameter = .{
                .name = param_name,
            } },
        });

        try fn_parameters.append(param);

        if (try self.maybe(.COMMA) == null) {
            _ = try self.expect(.RIGHT_PAREN); // If we break we need to check this.
            break;
        }
    }

    const body = try self.parseCodeBlock();

    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .function_def = .{
            .name = fn_name,
            .parameters = try fn_parameters.toOwnedSlice(),
            .body = body,
        } },
    });
}

// Parse native function declaration statement and return its ID if parsed.
// For more information please reference `ast.zig -> NativeFunctionDecl` struct.
pub fn parseMaybeNativeFunctionDeclStatement(self: *Self) !?usize {
    if (try self.maybe(.KW_NATIVE) == null) return null; // This may not be a native decl.
    try self.pushSpan();
    defer _ = self.popSpan();

    // ABI part of native function declaration is optional.
    const abi_maybe = try self.maybe(.STRING_LITERAL);
    const abi_node = if (abi_maybe) |abi| try self.tree.addNode(.{
        .span = abi.span,
        .kind = .{ .string_literal = abi.literal.string },
    }) else null;

    _ = try self.expect(.KW_FUNCTION);

    // This is very similar to the code in parseMaybeFunctionDefStatement.
    const fn_name = try self.expectIdentifier();
    _ = try self.expect(.LEFT_PAREN);

    var fn_parameters = std.ArrayList(usize).init(self.tree.allocator());
    errdefer fn_parameters.deinit(); // This may fail early.

    while (try self.maybe(.RIGHT_PAREN) == null) {
        const param_name = try self.expectIdentifier();
        try self.pushSpan();
        defer _ = self.popSpan();

        // Types are optional.
        var type_node: ?ast.NodeId = null;
        if (try self.maybe(.COLON) != null)
            type_node = try self.expectIdentifier();

        const param = try self.tree.addNode(.{
            .span = self.peekSpan(),
            .kind = .{ .native_parameter = .{
                .name = param_name,
                .type = type_node,
            } },
        });

        try fn_parameters.append(param);

        if (try self.maybe(.COMMA) == null) {
            _ = try self.expect(.RIGHT_PAREN); // If we break we need to check this.
            break;
        }
    }
    _ = try self.expect(.SEMICOLON);

    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .native_function_decl = .{
            .abi = abi_node,
            .name = fn_name,
            .parameters = try fn_parameters.toOwnedSlice(),
        } },
    });
}

pub fn parseMaybeCallOrAccess(self: *Self) !?usize {
    if ((try self.peek()).type != .IDENTIFIER) return null; // This may not be a call or access.

    const expr = try self.parseExpression();

    _ = try self.expect(.SEMICOLON);
    return expr;
}

// Parse block of code.
// This is basically a statement list inside of `{}` parentheses.
// This function assumes that caller has checked for `{` character already.
pub fn parseCodeBlock(self: *Self) !usize {
    _ = try self.expect(.LEFT_CURLY);
    try self.pushSpan();
    defer _ = self.popSpan();
    var block_contents = std.ArrayList(usize).init(self.tree.allocator());
    errdefer block_contents.deinit();
    while (try self.maybe(.RIGHT_CURLY) == null) {
        const stmt = try self.parseAnyStatement();
        try block_contents.append(stmt);
    }
    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .code_block = try block_contents.toOwnedSlice() },
    });
}

pub fn parseExpression(self: *Self) !usize {
    return try self.parseBinaryExpression(0); // 0 precedence means we can parse any expression.
}

// Parse expression and return its ID if parsed.
pub fn parseBinaryExpression(self: *Self, precedence: u8) !usize {
    var left = try self.parseAtom();

    while (true) {
        const next = try self.peek();
        const nextPrecedence = getPrecedence(next);

        if (nextPrecedence <= precedence) {
            // If next precedence is less than or equal to current precedence,
            // we stop parsing expressions.
            break;
        }

        _ = try self.expect(next.type);

        // Parse the right-hand side of the expression if assignment.
        const right = try parseBinaryExpression(self, if (nextPrecedence == 1) nextPrecedence - 1 else nextPrecedence);

        const left_node = self.tree.getNode(left).?;
        const right_node = self.tree.getNode(right).?;

        left = try self.tree.addNode(.{
            .span = .{
                .start = left_node.span.start,
                .end = right_node.span.end,
            },
            .kind = switch (nextPrecedence) {
                // Assignments:
                1 => .{
                    .assignment = .{
                        .operator = switch (next.type) {
                            .ASSIGN => .ASSIGN,
                            .ADD_ASSIGN => .ADD_ASSIGN,
                            .SUB_ASSIGN => .SUB_ASSIGN,
                            .MUL_ASSIGN => .MUL_ASSIGN,
                            .DIV_ASSIGN => .DIV_ASSIGN,
                            .MOD_ASSIGN => .MOD_ASSIGN,
                            .BITWISE_AND_ASSIGN => .BITWISE_AND_ASSIGN,
                            .BITWISE_OR_ASSIGN => .BITWISE_OR_ASSIGN,
                            .BITWISE_XOR_ASSIGN => .BITWISE_XOR_ASSIGN,
                            else => unreachable,
                        },
                        .target = left,
                        .value = right,
                    },
                },
                else => .{
                    .binary_operator = .{
                        .left = left,
                        .operator = switch (next.type) {
                            .MULTIPLY => .MULTIPLY,
                            .DIVIDE => .DIVIDE,
                            .MODULO => .MODULO,
                            .ADD => .ADD,
                            .SUBTRACT => .SUBTRACT,
                            .BITSHIFT_RIGHT => .BITSHIFT_RIGHT,
                            .BITSHIFT_LEFT => .BITSHIFT_LEFT,
                            .LESS_THAN => .LESS_THAN,
                            .LESS_EQUAL => .LESS_EQUAL,
                            .GREATER_THAN => .GREATER_THAN,
                            .GREATER_EQUAL => .GREATER_EQUAL,
                            .EQ_EQ => .EQ_EQ,
                            .NOT_EQ => .NOT_EQ,
                            .BITWISE_AND => .BITWISE_AND,
                            .BITWISE_XOR => .BITWISE_XOR,
                            .BITWISE_OR => .BITWISE_OR,
                            .LOGICAL_AND => .LOGICAL_AND,
                            .LOGICAL_OR => .LOGICAL_OR,
                            else => unreachable,
                        },
                        .right = right,
                    },
                },
            },
        });
    }

    return left;
}

pub fn parseAtom(self: *Self) !usize {
    const token = try self.advance();

    return switch (token.type) {
        .INTEGER_LITERAL => try self.tree.addNode(.{
            .span = token.span,
            .kind = .{ .integer_literal = token.literal.integer },
        }),
        .FLOAT_LITERAL => try self.tree.addNode(.{
            .span = token.span,
            .kind = .{ .float_literal = token.literal.float },
        }),
        .STRING_LITERAL => try self.tree.addNode(.{
            .span = token.span,
            .kind = .{ .string_literal = token.literal.string },
        }),
        .KW_TRUE, .KW_FALSE => try self.tree.addNode(.{
            .span = token.span,
            .kind = .{ .boolean_literal = token.type == .KW_TRUE },
        }),
        .BANG, .BITWISE_NOT, .SUBTRACT => try self.parseUnaryOperator(token),
        .LEFT_PAREN => try self.parseParenthesizedExpr(),
        .IDENTIFIER => {
            try self.pushSpan();
            defer _ = self.popSpan();

            const iden = try self.tree.addNode(.{
                .span = token.span,
                .kind = .{ .identifier = token.lexeme },
            });

            const next = try self.peek();
            if (next.type == .INCREMENT or next.type == .DECREMENT or next.type == .DOT or next.type == .LEFT_PAREN) {
                // This is a function call or member access (or just incrementation/decrementation).
                // We will handle it in a separate function.
                return try self.parsePostfix(iden);
            }

            return iden;
        },
        else => return self.reportError(
            "P003",
            "Expected an expression atom.",
            .{},
            error.ExpectedExpressionAtom,
            .{
                .labels = &.{.{
                    .color = .{ .basic = .magenta },
                    .span = token.span.asReportz(),
                    .message = "Found this instead.",
                }},
            },
        ),
    };
}

pub fn parseUnaryOperator(self: *Self, operator_token: Token) Self.Error!usize {
    try self.pushSpan();
    defer _ = self.popSpan();
    const operand = try self.parseAtom();
    return try self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{
            .unary_operator = .{
                .operator = switch (operator_token.type) {
                    .BANG => .NOT,
                    .BITWISE_NOT => .BITWISE_NOT,
                    .SUBTRACT => .SUBTRACT, // Unary minus
                    else => unreachable,
                },
                .operand = operand,
            },
        },
    });
}

pub fn parsePostfix(self: *Self, operand: usize) Self.Error!usize {
    try self.pushSpan();
    defer _ = self.popSpan();

    var expr = operand;

    while (true) {
        const next = try self.peek();

        switch (next.type) {
            .INCREMENT, .DECREMENT => {
                _ = try self.expect(next.type);
                expr = try self.tree.addNode(.{ .span = self.peekSpan(), .kind = .{
                    .unary_operator = .{
                        .operator = switch (next.type) {
                            .INCREMENT => .INCREMENT,
                            .DECREMENT => .DECREMENT,
                            else => unreachable,
                        },
                        .operand = expr,
                    },
                } });
                break;
            },
            .DOT => {
                _ = try self.expect(.DOT);

                const member = try self.expectIdentifier();

                expr = try self.tree.addNode(.{
                    .span = self.peekSpan(),
                    .kind = .{
                        .member_access = .{
                            .target = expr,
                            .member = member,
                        },
                    },
                });
            },
            .LEFT_PAREN => {
                _ = try self.expect(.LEFT_PAREN);
                var args = std.ArrayList(usize).init(self.tree.allocator());
                errdefer args.deinit(); // This may fail early.

                while (try self.maybe(.RIGHT_PAREN) == null) {
                    const arg = try self.parseExpression();
                    try args.append(arg);
                    if (try self.maybe(.COMMA) == null) {
                        _ = try self.expect(.RIGHT_PAREN); // If we break we need to check this.
                        break;
                    }
                }

                expr = try self.tree.addNode(.{
                    .span = self.peekSpan(),
                    .kind = .{
                        .function_call = .{
                            .name = expr,
                            .arguments = try args.toOwnedSlice(),
                        },
                    },
                });
            },
            else => break,
        }
    }

    return expr;
}

pub fn parseParenthesizedExpr(self: *Self) Self.Error!usize {
    try self.pushSpan();
    defer _ = self.popSpan();

    const expr = try self.parseExpression();
    _ = try self.expect(.RIGHT_PAREN);

    return self.tree.addNode(.{
        .span = self.peekSpan(),
        .kind = .{ .expression_group = .{
            .expression = expr,
        } },
    });
}

pub fn getPrecedence(op: Token) u8 {
    switch (op.type) {
        .MULTIPLY, .DIVIDE, .MODULO => return 11,
        .ADD, .SUBTRACT => return 10,
        .BITSHIFT_RIGHT, .BITSHIFT_LEFT => return 9,
        .LESS_THAN, .LESS_EQUAL, .GREATER_THAN, .GREATER_EQUAL => return 8,
        .EQ_EQ, .NOT_EQ => return 7,
        .BITWISE_AND => return 6,
        .BITWISE_XOR => return 5,
        .BITWISE_OR => return 4,
        .LOGICAL_AND => return 3,
        .LOGICAL_OR => return 2,
        .ASSIGN, .ADD_ASSIGN, .SUB_ASSIGN, .MUL_ASSIGN, .DIV_ASSIGN, .MOD_ASSIGN, .BITWISE_AND_ASSIGN, .BITWISE_OR_ASSIGN, .BITWISE_XOR_ASSIGN => return 1,
        else => return 0, // No precedence for other tokens.
    }
}

test "parseWholeSource method should parse multiple statements" {
    const source =
        \\import "source.brr";
        \\import "another.brr" as another;
    ;
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const module = try parser.parseWholeSource();
    const module_node = parser.tree.getNodeUnsafe(module);
    try std.testing.expectEqualDeep(common.Span{ .start = 0, .end = 53 }, module_node.span);
    try std.testing.expectEqualDeep("module", @tagName(module_node.kind));
    const body_node = parser.tree.getNodeUnsafe(module_node.kind.module.body);
    try std.testing.expectEqual(2, body_node.kind.code_block.len);
}

test "Parse `import` statement" {
    const source =
        \\import "source.brr";
        \\import "another.brr" as another;
    ;
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const import_1 = (try parser.parseMaybeImportStatement()).?;
    const import_1_node = parser.tree.getNodeUnsafe(import_1);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 20 },
        .kind = .{ .import = .{
            .source = 0,
            .opt_rename = null,
        } },
    }, import_1_node);

    const import_2 = (try parser.parseMaybeImportStatement()).?;
    const import_2_node = parser.tree.getNodeUnsafe(import_2);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 21, .end = 53 },
        .kind = .{ .import = .{
            .source = 2,
            .opt_rename = 3,
        } },
    }, import_2_node);
}

test "Parse function definition statement" {
    const source = "fn lorem(hello, world) {}";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const fn_id = (try parser.parseMaybeFunctionDefStatement()).?;
    const fn_node = parser.tree.getNodeUnsafe(fn_id);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 25 },
        .kind = .{ .function_def = .{
            .name = 0,
            .parameters = &.{ 2, 4 },
            .body = 5,
        } },
    }, fn_node);
}

test "Parse variable declaration statement" {
    const source = "brr x = 42;";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const var_id = (try parser.parseMaybeVariableDeclaration()).?;
    const var_node = parser.tree.getNodeUnsafe(var_id);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 11 },
        .kind = .{ .variable = .{
            .name = 0,
            .expression = 1,
        } },
    }, var_node);
}

test "Parse constant declaration statement" {
    const source = "const X = 42;";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const const_id = (try parser.parseMaybeConstantDeclaration()).?;
    const const_node = parser.tree.getNodeUnsafe(const_id);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 13 },
        .kind = .{ .constant = .{
            .name = 0,
            .expression = 1,
        } },
    }, const_node);
}

test "Parse native function declaration statement" {
    const source = "native \"C\" fn lorem(hello: i32, world);";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const fn_id = (try parser.parseMaybeNativeFunctionDeclStatement()).?;
    const fn_node = parser.tree.getNodeUnsafe(fn_id);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 39 },
        .kind = .{ .native_function_decl = .{
            .abi = 0,
            .name = 1,
            .parameters = &.{ 4, 6 },
        } },
    }, fn_node);
}

test "Parse code block" {
    const source = "{import \"hello.brr\";}";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const block = try parser.parseCodeBlock();
    const block_node = parser.tree.getNodeUnsafe(block);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 21 },
        .kind = .{ .code_block = &.{1} },
    }, block_node);
}

test "Parse broken simple addition expression expecting error" {
    const source = "2 + ";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    try std.testing.expectError(
        error.ExpectedExpressionAtom,
        parser.parseExpression(),
    );
}

test "Parse simple addition expression" {
    const source = "2 + 2";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    // Parse the expression
    const expr_id = try parser.parseExpression();
    const expr_node = parser.tree.getNode(expr_id).?;

    // Verify root node structure
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 5 },
        .kind = .{
            .binary_operator = .{
                .left = 0, // Left operand ID
                .operator = .ADD,
                .right = 1, // Right operand ID
            },
        },
    }, expr_node);

    // Verify left operand (first '2')
    const left_node = parser.tree.getNode(expr_node.kind.binary_operator.left).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 1 },
        .kind = .{ .integer_literal = 2 },
    }, left_node);

    // Verify right operand (second '2')
    const right_node = parser.tree.getNode(expr_node.kind.binary_operator.right).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 4, .end = 5 },
        .kind = .{ .integer_literal = 2 },
    }, right_node);
}

test "Parse expression with parentheses" {
    const source = "(2 + 3) * 4";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    // Parse the expression
    const expr_id = try parser.parseExpression();
    const expr_node = parser.tree.getNode(expr_id).?;

    // Root node: *
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 11 },
        .kind = .{
            .binary_operator = .{
                .left = 3,
                .operator = .MULTIPLY,
                .right = 4,
            },
        },
    }, expr_node);

    // Left operand: (2 + 3)
    const left_mul = parser.tree.getNode(3).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 7 },
        .kind = .{
            .expression_group = .{
                .expression = 2,
            },
        },
    }, left_mul);

    // Inside parentheses: 2 + 3
    const in_brackets = parser.tree.getNode(2).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 1, .end = 6 },
        .kind = .{
            .binary_operator = .{
                .left = 0,
                .operator = .ADD,
                .right = 1,
            },
        },
    }, in_brackets);

    // Right operand: 4
    const right_mul = parser.tree.getNode(4).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 10, .end = 11 },
        .kind = .{ .integer_literal = 4 },
    }, right_mul);

    // Left operand of +
    const left_add = parser.tree.getNode(0).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 1, .end = 2 },
        .kind = .{ .integer_literal = 2 },
    }, left_add);

    // Right operand of +
    const right_add = parser.tree.getNode(1).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 5, .end = 6 },
        .kind = .{ .integer_literal = 3 },
    }, right_add);
}

test "Parse complex expression with operators" {
    const source = "-2 == 8 * 4 / (2 + abc++) || a > ~b + 3";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const expr_id = try parser.parseExpression();
    const expr_node = parser.tree.getNode(expr_id).?;

    // IDs assigned in order:
    //
    // 0: integer_literal 2
    // 1: unary_operator -2
    // 2: integer_literal 8
    // 3: integer_literal 4
    // 4: binary_operator 8 * 4
    // 5: integer_literal 2
    // 6: identifier "abc"
    // 7: unary_operator abc++
    // 8: brackets (2 + abc++)
    // 9: binary_operator 2 + abc++
    //10: binary_operator (8*4) / (2 + abc++)
    //11: binary_operator (-2) == (...)
    //12: identifier "a"
    //13: identifier "b"
    //14: unary_operator ~b
    //15: integer_literal 3
    //16: binary_operator (~b) + 3
    //17: binary_operator a > (...)
    //18: binary_operator (...) || (...)

    //
    // Now we validate from the top down:
    //

    // Top: OR
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = source.len },
        .kind = .{
            .binary_operator = .{
                .left = 11,
                .operator = .LOGICAL_OR,
                .right = 17,
            },
        },
    }, expr_node);

    // Left of OR: ==
    const eq_node = parser.tree.getNode(11).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 25 },
        .kind = .{
            .binary_operator = .{
                .left = 1,
                .operator = .EQ_EQ,
                .right = 10,
            },
        },
    }, eq_node);

    // Right of OR: >
    const gt_node = parser.tree.getNode(17).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 29, .end = 39 },
        .kind = .{
            .binary_operator = .{
                .left = 12,
                .operator = .GREATER_THAN,
                .right = 16,
            },
        },
    }, gt_node);

    // Left operand of ==
    const minus2 = parser.tree.getNode(1).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 2 },
        .kind = .{
            .unary_operator = .{
                .operator = .SUBTRACT,
                .operand = 0,
            },
        },
    }, minus2);

    // literal 2
    const lit2 = parser.tree.getNode(0).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 1, .end = 2 },
        .kind = .{ .integer_literal = 2 },
    }, lit2);

    // Right operand of ==
    const div_node = parser.tree.getNode(10).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 6, .end = 25 },
        .kind = .{
            .binary_operator = .{
                .left = 4,
                .operator = .DIVIDE,
                .right = 9,
            },
        },
    }, div_node);

    // 8 * 4
    const mul_node = parser.tree.getNode(4).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 6, .end = 11 },
        .kind = .{
            .binary_operator = .{
                .left = 2,
                .operator = .MULTIPLY,
                .right = 3,
            },
        },
    }, mul_node);

    // 8 literal
    const lit8 = parser.tree.getNode(2).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 6, .end = 7 },
        .kind = .{ .integer_literal = 8 },
    }, lit8);

    // 4 literal
    const lit4 = parser.tree.getNode(3).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 10, .end = 11 },
        .kind = .{ .integer_literal = 4 },
    }, lit4);

    // (2 + abc++)
    const plus_node_in_brackets = parser.tree.getNode(9).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 14, .end = 25 },
        .kind = .{
            .expression_group = .{
                .expression = 8,
            },
        },
    }, plus_node_in_brackets);

    const plus_node = parser.tree.getNode(8).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 15, .end = 24 },
        .kind = .{
            .binary_operator = .{
                .left = 5,
                .operator = .ADD,
                .right = 7,
            },
        },
    }, plus_node);

    // literal 2
    const lit2b = parser.tree.getNode(5).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 15, .end = 16 },
        .kind = .{ .integer_literal = 2 },
    }, lit2b);

    // abc++
    const inc_node = parser.tree.getNode(7).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 19, .end = 24 },
        .kind = .{
            .unary_operator = .{
                .operator = .INCREMENT,
                .operand = 6,
            },
        },
    }, inc_node);

    // abc identifier
    const id_abc = parser.tree.getNode(6).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 19, .end = 22 },
        .kind = .{ .identifier = "abc" },
    }, id_abc);

    // Left of >: a
    const id_a = parser.tree.getNode(12).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 29, .end = 30 },
        .kind = .{ .identifier = "a" },
    }, id_a);

    // (~b) + 3
    const plus_b3 = parser.tree.getNode(16).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 33, .end = 39 },
        .kind = .{
            .binary_operator = .{
                .left = 14,
                .operator = .ADD,
                .right = 15,
            },
        },
    }, plus_b3);

    // ~b
    const not_b = parser.tree.getNode(14).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 33, .end = 35 },
        .kind = .{
            .unary_operator = .{
                .operator = .BITWISE_NOT,
                .operand = 13,
            },
        },
    }, not_b);

    // identifier b
    const id_b = parser.tree.getNode(13).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 34, .end = 35 },
        .kind = .{ .identifier = "b" },
    }, id_b);

    // 3 literal
    const lit3 = parser.tree.getNode(15).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 38, .end = 39 },
        .kind = .{ .integer_literal = 3 },
    }, lit3);
}

test "Parse assignment" {
    const source = "a += b = 2";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    // Parse the expression
    const expr_id = try parser.parseExpression();
    const expr_node = parser.tree.getNode(expr_id).?;

    // Root node: assignment '+='
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 10 },
        .kind = .{
            .assignment = .{
                .operator = .ADD_ASSIGN,
                .target = 0,
                .value = 3,
            },
        },
    }, expr_node);

    // target of '+=': identifier 'a'
    const target_add_assign = parser.tree.getNode(0).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 1 },
        .kind = .{ .identifier = "a" },
    }, target_add_assign);

    // value of '+=': assignment '='
    const value_add_assign = parser.tree.getNode(3).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 5, .end = 10 },
        .kind = .{
            .assignment = .{
                .operator = .ASSIGN,
                .target = 1,
                .value = 2,
            },
        },
    }, value_add_assign);

    // target of '=': identifier 'b'
    const target_assign = parser.tree.getNode(1).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 5, .end = 6 },
        .kind = .{ .identifier = "b" },
    }, target_assign);

    // value of '=': integer literal 2
    const value_assign = parser.tree.getNode(2).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 9, .end = 10 },
        .kind = .{ .integer_literal = 2 },
    }, value_assign);
}

test "Parse complex postfix expression" {
    const source = "abc().def.ghi().j++;";
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const expr_id = (try parser.parseMaybeCallOrAccess()).?;
    const expr_node = parser.tree.getNode(expr_id).?;

    // postfix ++ on member_access ( .j )
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 19 },
        .kind = .{
            .unary_operator = .{
                .operator = .INCREMENT,
                .operand = 8, // member_access .j
            },
        },
    }, expr_node);

    // member_access .j applied to function_call ghi()
    const member_j = parser.tree.getNode(8).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 17 },
        .kind = .{
            .member_access = .{
                .target = 6, // function_call ghi()
                .member = 7, // identifier j
            },
        },
    }, member_j);

    // identifier j
    const ident_j = parser.tree.getNode(7).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 16, .end = 17 },
        .kind = .{ .identifier = "j" },
    }, ident_j);

    // function_call ghi()
    const func_ghi = parser.tree.getNode(6).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 15 },
        .kind = .{
            .function_call = .{
                .name = 5, // member_access .ghi
                .arguments = &[_]usize{},
            },
        },
    }, func_ghi);

    // member_access .ghi applied to member_access .def
    const member_ghi = parser.tree.getNode(5).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 13 },
        .kind = .{
            .member_access = .{
                .target = 3, // member_access .def
                .member = 4, // identifier ghi
            },
        },
    }, member_ghi);

    // identifier ghi
    const ident_ghi = parser.tree.getNode(4).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 10, .end = 13 },
        .kind = .{ .identifier = "ghi" },
    }, ident_ghi);

    // member_access .def applied to function_call abc()
    const member_def = parser.tree.getNode(3).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 9 },
        .kind = .{
            .member_access = .{
                .target = 1, // function_call abc()
                .member = 2, // identifier def
            },
        },
    }, member_def);

    // identifier def
    const ident_def = parser.tree.getNode(2).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 6, .end = 9 },
        .kind = .{ .identifier = "def" },
    }, ident_def);

    // function_call abc()
    const func_abc = parser.tree.getNode(1).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 5 },
        .kind = .{
            .function_call = .{
                .name = 0, // identifier abc
                .arguments = &[_]usize{},
            },
        },
    }, func_abc);

    // identifier abc
    const ident_abc = parser.tree.getNode(0).?;
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 3 },
        .kind = .{ .identifier = "abc" },
    }, ident_abc);
}
