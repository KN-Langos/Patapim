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

// Get current span from the stack.
// This function assumes that stack is not empty.
fn popSpan(self: *Self) common.Span {
    const span_start = self.span_stack.pop().?;
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

// Parse import statement and return its ID if parsed.
// For more information please reference `ast.zig -> Import` struct.
pub fn parseMaybeImportStatement(self: *Self) !?usize {
    if (try self.maybe(.KW_IMPORT) == null) return null; // This may not be an import statement.
    try self.pushSpan();
    const source_path = try self.expect(.STRING_LITERAL);
    const source_path_node = try self.tree.addNode(.{
        .span = source_path.span,
        .kind = .{ .string_literal = source_path.literal.string },
    });
    if (try self.maybe(.KW_AS) != null) {
        const import_rename_node = try self.expectIdentifier();
        return try self.tree.addNode(.{
            .span = self.popSpan(),
            .kind = .{ .import = .{
                .source = source_path_node,
                .opt_rename = import_rename_node,
            } },
        });
    } else return try self.tree.addNode(.{
        .span = self.popSpan(),
        .kind = .{ .import = .{
            .source = source_path_node,
        } },
    });
}

test "Parse `import` statement" {
    // There are no semicolons because this only tests one sub-parser.
    const source =
        \\import "source.brr"
        \\import "another.brr" as another
    ;
    var lexer: Lexer = .{ .source = source };
    var parser = Self.init(std.testing.allocator, &lexer);
    defer parser.deinit(true);

    const import_1 = (try parser.parseMaybeImportStatement()).?;
    const import_1_node = parser.tree.getNodeUnsafe(import_1);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 0, .end = 19 },
        .kind = .{ .import = .{
            .source = 0,
            .opt_rename = null,
        } },
    }, import_1_node);

    const import_2 = (try parser.parseMaybeImportStatement()).?;
    const import_2_node = parser.tree.getNodeUnsafe(import_2);
    try std.testing.expectEqualDeep(ast.Node{
        .span = .{ .start = 20, .end = 51 },
        .kind = .{ .import = .{
            .source = 2,
            .opt_rename = 3,
        } },
    }, import_2_node);
}
