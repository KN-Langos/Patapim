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
        const param = try self.tree.addNode(.{
            .span = self.tree.getNodeUnsafe(param_name).span, // This exists for sure.
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
    const source =
        \\fn lorem(hello, world) {}
    ;
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
