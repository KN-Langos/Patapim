//! Main implementation of the Patapim lexer.
//! This file is responsible for generation of so called tokens from source files.

const std = @import("std");

const reportz = @import("reportz");

const common = @import("common.zig");

// Start index of the current token.
// This is used for generation of proper spans.
start: usize = 0,
// Current index when parsing tokens.
// Often the end of token span.
current: usize = 0,
// ID of the source being scanned.
// This defaults to "internal<lexer>".
source_id: []const u8 = "internal<lexer>",
// Slice of source code.
source: []const u8,

// Error that this lexer produced.
// Lexer should only produce one error before failing the compilation
diagnostic: ?reportz.reports.Diagnostic = null,

const Self = @This();
const LOG = std.log.scoped(.lexer);

pub const Error = error{
    InvalidToken,
    UnterminatedMultilineComment,
    InvalidNumberLiteral,
};

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
    .{ "struct", .KW_STRUCT },
    .{ "enum", .KW_ENUM },
    .{ "true", .KW_TRUE },
    .{ "false", .KW_FALSE },
    .{ "if", .KW_IF },
    .{ "else", .KW_ELSE },
    .{ "return", .KW_RETURN },
    .{ "error", .KW_ERROR },
    .{ "loop", .KW_LOOP },
    .{ "while", .KW_WHILE },
    .{ "do", .KW_DO },
    .{ "for", .KW_FOR },
    .{ "break", .KW_BREAK },
    .{ "continue", .KW_CONTINUE },
    .{ "in", .KW_IN },
    .{ "fn", .KW_FUNCTION },
    .{ "brr", .KW_VARIABLE },
    .{ "const", .KW_CONST },
    .{ "native", .KW_NATIVE },
    .{ "iserror", .KW_ISERROR },
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
    KW_STRUCT,
    KW_ENUM,
    KW_TRUE,
    KW_FALSE,
    KW_IF,
    KW_ELSE,
    KW_RETURN,
    KW_ERROR,
    KW_LOOP,
    KW_WHILE,
    KW_DO,
    KW_FOR,
    KW_BREAK,
    KW_CONTINUE,
    KW_IN,
    KW_FUNCTION,
    KW_VARIABLE,
    KW_CONST,
    KW_NATIVE,
    KW_ISERROR,

    // Special tokens:
    INTEGER_LITERAL,
    FLOAT_LITERAL,
    IDENTIFIER,
    EOF, // End of file.
};

// Internal method for reporting error diagnostics.
// This should be called in place of `error.*` whenever returning any errors.
// Please examine the code below to get more details on usage before implementing new features.
fn reportError(self: *Self, code: []const u8, message: []const u8, error_type: Self.Error) Self.Error {
    // This tells the compiler this function is unlikely to be called.
    @branchHint(.cold);

    self.diagnostic = reportz.reports.Diagnostic{
        .source_id = self.source_id,
        .severity = .@"error",
        .code = code,
        .message = message,
        .labels = &.{
            reportz.reports.Label{
                .color = .{ .basic = .magenta },
                .message = "During scanning of this token",
                .span = .{ .start = self.start, .end = self.current },
            },
        },
    };

    return error_type;
}

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
    try self.skipWhitespaceAndComments();
    self.start = self.current; // Update start index after comments and ws.
    if (self.isAtEnd()) return eof;

    const char = self.source[self.current];
    var literal_value: LiteralValue = .none;

    // Match token with predefined list.
    const token_type = switch (char) {
        '(' => .LEFT_PAREN,
        ')' => .RIGHT_PAREN,
        '{' => .LEFT_CURLY,
        '}' => .RIGHT_CURLY,
        '[' => .LEFT_SQUARE,
        ']' => .RIGHT_SQUARE,

        'A'...'Z', 'a'...'z', '_' => self.lexIdentifierOrKW(),
        '0'...'9' => try self.lexNumber(&literal_value),
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

// Lex any number.
// This function parses an number and then attempts to match
// it as integer or float.
// This implementation is still missing support for exponential notation,
// but it can be extended in the future.
fn lexNumber(self: *Self, literal_value: *LiteralValue) !TokenType {
    // Make space for clean number buffer.
    var clean_buffer: [128]u8 = undefined;
    var clean_len: usize = 0;

    var is_float: bool = false;
    var last_char_is_digit: bool = true;
    var base: u8 = 10; // Default base is decimal.

    // Parse until end of number.
    var char = self.source[self.current];

    if (!self.isAtEnd() and char == '0') {
        const next_char = if (self.current + 1 < self.source.len) self.source[self.current + 1] else '?';
        self.current += 2; // Skip '0' and next character.
        switch (next_char) {
            'b', 'B' => {
                base = 2; // Binary.
                if (self.isAtEnd()) return self.reportError("L06", "Invalid number literal. Expected binary number after '0b'.", error.InvalidNumberLiteral);
                char = self.source[self.current];
            },
            'o', 'O' => {
                base = 8; // Octal.
                if (self.isAtEnd()) return self.reportError("L07", "Invalid number literal. Expected octal number after '0o'.", error.InvalidNumberLiteral);
                char = self.source[self.current];
            },
            'x', 'X' => {
                base = 16; // Hexadecimal.
                if (self.isAtEnd()) return self.reportError("L08", "Invalid number literal. Expected hexadecimal number after '0x'.", error.InvalidNumberLiteral);
                char = self.source[self.current];
            },
            else => {
                self.current -= 2; // Roll back to '0'.
            },
        }
    }

    while (!self.isAtEnd()) {
        if (isValidDigitForBase(char, base)) {
            clean_buffer[clean_len] = char;
            clean_len += 1;
            last_char_is_digit = true;
        } else if (char == '_') {
            last_char_is_digit = false;
        } else if (char == '.') {
            // If we already have a dot, this is not a valid number.
            if (is_float) return self.reportError("L02", "Floating number has multiple dots.", error.InvalidNumberLiteral);

            // If we have a dot, it must be in decimal numbers.
            if (base != 10) return self.reportError("L09", "Floating point numbers are only supported in decimal base.", error.InvalidNumberLiteral);

            clean_buffer[clean_len] = char;
            clean_len += 1;
            last_char_is_digit = false;
            is_float = true;
        } else {
            break; // End of number.
        }

        self.current += 1;
        if (!self.isAtEnd()) char = self.source[self.current];
    }

    // If last character is not a digit, this is not a valid number.
    if (!last_char_is_digit) return self.reportError("L03", "Last character in numeric literal may not be '_'.", error.InvalidNumberLiteral);

    const cleaned_str = clean_buffer[0..clean_len];
    self.current -= 1; // ".next()" function advances current, so we roll back one.

    if (is_float) {
        // If we have a float, parse it as float.
        // If it fails, it means that the number is not valid.
        const parsed_float = std.fmt.parseFloat(f64, cleaned_str) catch |err| {
            LOG.err("Error while calling parseFloat(...). This should not occur! Error message: {any}", .{err});
            return self.reportError("L04", "Invalid number literal. If you see this please open an issue on github.", error.InvalidNumberLiteral);
        };

        // Return float token type and modify literal value.
        literal_value.* = .{ .float = parsed_float };
        return TokenType.FLOAT_LITERAL;
    }

    // Else parse the number as integer.
    // If it fails, it means that the number is not valid.
    const parsed_int = std.fmt.parseInt(u64, cleaned_str, base) catch |err| {
        LOG.err("Error while calling parseInt(...). This should not occur! Error message: {any}", .{err});
        return self.reportError("L05", "Invalid number literal. If you see this please open an issue on github.", error.InvalidNumberLiteral);
    };

    // Return integer token type and modify literal value.
    literal_value.* = .{ .integer = parsed_int };
    return TokenType.INTEGER_LITERAL;
}

fn isValidDigitForBase(c: u8, base: u8) bool {
    // Check if character is a valid digit for given base.
    // For bases 2, 8, 10, and 16.
    return switch (base) {
        2 => c == '0' or c == '1',
        8 => c >= '0' and c <= '7',
        10 => c >= '0' and c <= '9',
        16 => (c >= '0' and c <= '9') or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f'),
        else => false, // Invalid base.
    };
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
                    return self.reportError("L01", "Unterminated multiline comment.", error.UnterminatedMultilineComment);
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

test "Lex numbers" {
    const source = "123 4_567_890 42.321 0b1010 0o67 0x1F4 0";
    var lexer = Self{ .source = source };

    try std.testing.expectEqualDeep(Token{
        .type = .INTEGER_LITERAL,
        .span = .{ .start = 0, .end = 3 },
        .lexeme = "123",
        .literal = .{ .integer = 123 },
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .INTEGER_LITERAL,
        .span = .{ .start = 4, .end = 13 },
        .lexeme = "4_567_890",
        .literal = .{ .integer = 4567890 },
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .FLOAT_LITERAL,
        .span = .{ .start = 14, .end = 20 },
        .lexeme = "42.321",
        .literal = .{ .float = 42.321 },
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .INTEGER_LITERAL,
        .span = .{ .start = 21, .end = 27 },
        .lexeme = "0b1010",
        .literal = .{ .integer = 10 },
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .INTEGER_LITERAL,
        .span = .{ .start = 28, .end = 32 },
        .lexeme = "0o67",
        .literal = .{ .integer = 55 },
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .INTEGER_LITERAL,
        .span = .{ .start = 33, .end = 38 },
        .lexeme = "0x1F4",
        .literal = .{ .integer = 500 },
    }, try lexer.next());

    try std.testing.expectEqualDeep(Token{
        .type = .INTEGER_LITERAL,
        .span = .{ .start = 39, .end = 40 },
        .lexeme = "0",
        .literal = .{ .integer = 0 },
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
