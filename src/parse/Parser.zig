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
    };
}

pub fn deinit(self: *Self, deinit_tree: bool) void {
    if (deinit_tree) // We may want to keep the tree for further passes or interpreter.
        self.tree.deinit();
    self.diagnostic_log.deinit();
    self.diagnostic_arena.deinit();
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

    self.diagnostic_log.append(reportz.reports.Diagnostic{
        .source_id = self.lexer.source_id,
        .severity = additional_options.severity,
        .code = code,
        .message = std.fmt.allocPrint(diagnostic_alloc, message_fmt, message_args),
        // This ensures that labels and notes live at least as long as diagnostic_log field.
        .labels = common.deepClone(
            []const reportz.reports.Label,
            additional_options.labels,
            diagnostic_alloc,
        ),
        .notes = common.deepClone(
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
    self.cached_token = try self.lexer.next();
    return self.cached_token.?; // We may do `.?` because we set it above.
}

// Advance one token forward and return current token.
fn advance(self: *Self) !Token {
    const current_token = self.peek();
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

// ---< Helper and utility functions end >---
