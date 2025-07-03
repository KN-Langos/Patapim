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

pub const Error = error{ InvalidToken, UnterminatedMultilineComment };

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

pub const KEYWORD_MAP: std.StaticStringMap(TokenType) = .initComptime(.{
    .{ "import", .KW_IMPORT },
    .{ "as", .KW_AS },
    // TODO: [...]
});

pub const TokenType = enum {
    // Parentheses:
    LEFT_PAREN, // '('
    RIGHT_PAREN, // ')'
    LEFT_CURLY, // '{'
    RIGHT_CURLY, // '}'
    LEFT_SQUARE, // '['
    RIGHT_SQUARE, // ']'

    // Keywords:
    KW_IMPORT,
    KW_AS,
    // TODO: [...]

    // Special tokens:
    IDENTIFIER,
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
    try self.skipWhitespaceAndComments(); // TODO: Catch and pretty print error.
    self.start = self.current; // Update start index after comments and ws.
    if (self.isAtEnd()) return eof;

    // Match token with predefined list.
    const char = self.source[self.current];
    const literal_value: LiteralValue = .none;
    const token_type: TokenType = switch (char) {
        '(' => .LEFT_PAREN,
        ')' => .RIGHT_PAREN,
        '{' => .LEFT_CURLY,
        '}' => .RIGHT_CURLY,
        '[' => .LEFT_SQUARE,
        ']' => .RIGHT_SQUARE,

        'A'...'Z', 'a'...'z', '_' => self.lexIdentifierOrKW(),
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

// Lex any identifier or keyword.
// This function parses an identifier and then attempts to match
// it against known keyword map.
fn lexIdentifierOrKW(self: *Self) TokenType {
    // Parse until end of identifier.
    var char = self.source[self.current];
    while (!self.isAtEnd() and std.ascii.isAlphanumeric(char) or char == '-' or char == '_') {
        self.current += 1;
        if (!self.isAtEnd()) char = self.source[self.current];
    }

    // If exists in keyword map, return matching token.
    const lexeme = self.source[self.start..self.current];
    self.current -= 1; // ".next()" function advances current, so we roll back one.
    if (KEYWORD_MAP.get(lexeme)) |kw_token|
        return kw_token;

    // If not, return identifier token type.
    return TokenType.IDENTIFIER;
}

fn skipWhitespaceAndComments(self: *Self) !void {
    while (self.skipWhitespace() or try self.skipComment()) {
        // This will skip both.
    }
}

fn skipComment(self: *Self) !bool {
    if (self.isAtEnd()) return false; // Is this necessary? Maybe better to be safe.
    var char = self.source[self.current];
    var maybe_next = if (self.current + 1 < self.source.len)
        self.source[self.current + 1]
    else
        null;
    var has_skipped = false;

    // This is expensive. But runs only for comments so It should be fine.
    if (!self.isAtEnd() and char == '/' and (maybe_next == '/' or maybe_next == '*')) {
        has_skipped = true;
        if (maybe_next == '/') { // Single-line comments
            while (!self.isAtEnd() and char != '\n') {
                self.current += 1;
                if (!self.isAtEnd()) char = self.source[self.current];
            }
        } else { // Multi-line comments
            // Technically with this /*/ is a comment, but it seems unlikely to be an issue.
            while (char != '*' or maybe_next != '/') {
                self.current += 1;
                if (!self.isAtEnd()) {
                    char = self.source[self.current];
                    maybe_next = if (self.current + 1 < self.source.len)
                        self.source[self.current + 1]
                    else
                        null;
                } else {
                    return error.UnterminatedMultilineComment;
                }
            }
            self.current += 2; // Skip '*/'
        }
    }

    return has_skipped;
}

fn skipWhitespace(self: *Self) bool {
    if (self.isAtEnd()) return false; // Is this necessary? Maybe better to be safe.
    var char = self.source[self.current];
    var has_skipped = false;
    while (!self.isAtEnd() and std.ascii.isWhitespace(char)) {
        has_skipped = true;
        self.current += 1;
        if (!self.isAtEnd()) char = self.source[self.current];
    }
    return has_skipped;
}

test "Lex single character tokens" {
    const source = "(){}[]";
    var lexer = Self{ .source = source };

    for ([_]TokenType{
        .LEFT_PAREN,
        .RIGHT_PAREN,
        .LEFT_CURLY,
        .RIGHT_CURLY,
        .LEFT_SQUARE,
        .RIGHT_SQUARE,
    }, 0..) |expected_token_type, idx| {
        const expected_token = Token{
            .type = expected_token_type,
            .span = .{ .start = idx, .end = idx + 1 },
            .lexeme = source[idx .. idx + 1],
        };
        try std.testing.expectEqualDeep(expected_token, try lexer.next());
    }
}

test "Lex keywords and identifiers" {
    const source = "simple with_underscore import";
    var lexer = Self{ .source = source };

    try std.testing.expectEqualDeep(Token{
        .type = .IDENTIFIER,
        .span = .{ .start = 0, .end = 6 },
        .lexeme = "simple",
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .IDENTIFIER,
        .span = .{ .start = 7, .end = 22 },
        .lexeme = "with_underscore",
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .KW_IMPORT,
        .span = .{ .start = 23, .end = 29 },
        .lexeme = "import",
    }, try lexer.next());
}

test "Lex comments and whitespace characters" {
    const source =
        \\ // This is a first comment.
        \\ // This is a second comment.
        \\
        \\ // And this one is preceded with newline
        \\ /* I am multiline
        \\ comment */
    ;
    var lexer = Self{ .source = source };

    try std.testing.expectEqualDeep(Token{
        .type = .EOF,
        .span = .{ .start = source.len, .end = source.len },
        .lexeme = "",
    }, try lexer.next());
}
