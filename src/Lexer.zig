//! Main implementation of the Patapim lexer.
//! This file is responsible for generation of so called tokens from source files.

const std = @import("std");

const common = @import("common.zig");

// Start index of the current token.
// This is used for generation of proper spans.
start: usize = 0,
// Current index when parsing tokens.
// Often the end of token span.
current: usize = 0,
// Slice of source code.
source: []const u8,

const Self = @This();
const LOG = std.log.scoped(.lexer);

pub const Error = error{InvalidToken};

pub const LiteralValue = union(enum) {
    none: void,
    integer: u64,
    float: f64,
};

pub const Token = struct {
    type: TokenType,
    span: common.Span,
    // Lexeme is a slice of source code that produced this token.
    lexeme: []const u8,
    literal: LiteralValue = .none,
};

pub const TokenType = enum {
    // Parentheses:
    LEFT_PAREN, // '('
    RIGHT_PAREN, // ')'
    LEFT_CURLY, // '{'
    RIGHT_CURLY, // '}'
    LEFT_SQUARE, // '['
    RIGHT_SQUARE, // ']'

    // Special tokens:
    EOF, // End of file.
};

// Check whether lexer has reached the end of source being scanned.
pub inline fn isAtEnd(self: *Self) bool {
    return self.current >= self.source.len;
}

// Generate next token. This function neither allocates nor stores the token.
// Peeking functionality is implemented in the parser.
pub fn next(self: *Self) Self.Error!Token {
    const eof = Token{
        .type = .EOF,
        // EOF span has no length. It starts and ends at the end of source code.
        .span = .{ .start = self.source.len, .end = self.source.len },
        .lexeme = self.source[self.source.len..self.source.len],
    };

    if (self.isAtEnd()) return eof;

    var char = self.source[self.current];

    // Skip whitespace characters.
    while (std.ascii.isWhitespace(char)) : (char = self.source[self.current])
        self.current += 1;
    self.start = self.current;

    // Fetch next token if exists.
    const next_char: ?u8 = if (self.current + 1 < self.source.len) self.source[self.current] else null;

    // Skip comments
    if (char == '/' and next_char == '/') {
        // Skip until newline character.
        while (char != '\n') : (char = self.source[self.current])
            self.current += 1;
        self.start = self.current;
    }
    if (self.isAtEnd()) return eof;

    // Match token with predefined list.
    const literal_value: LiteralValue = .none;
    const token_type: TokenType = switch (char) {
        '(' => .LEFT_PAREN,
        ')' => .RIGHT_PAREN,
        '{' => .LEFT_CURLY,
        '}' => .LEFT_CURLY,
        '[' => .LEFT_SQUARE,
        ']' => .RIGHT_SQUARE,

        else => return error.InvalidToken,
    };

    // Generate token, update lexer state, and return.
    self.current += 1;
    const result_token = Token{
        .type = token_type,
        .span = .{ .start = self.start, .end = self.current },
        .lexeme = self.source[self.start..self.current],
        .literal = literal_value,
    };
    self.start = self.current;
    LOG.debug("Generated token '{any}'@{d}:{d} - \"{s}\" ({any})", .{
        token_type,
        result_token.span.start,
        result_token.span.end,
        result_token.lexeme,
        result_token.literal,
    });
    return result_token;
}
