const std = @import("std");

/// The different types of tokens that our Key-Value store understands.
pub const TokenType = enum {
    SET,
    GET,
    DELETE,
    IDENTIFIER,
    STRING,
    NUMBER,
    EQUALS,
    SEMICOLON,
    EOF,
    ILLEGAL,
};

/// Represents a single symbol or word in the source code.
pub const Token = struct {
    type: TokenType,
    literal: []const u8,
};

/// Lexer takes a string input and breaks it down into tokens.
pub const Lexer = struct {
    input: []const u8,
    position: usize = 0,
    read_position: usize = 0,
    ch: u8 = 0,

    /// Creates a new Lexer instance.
    pub fn init(input: []const u8) Lexer {
        var l = Lexer{ .input = input };
        l.readChar();
        return l;
    }

    /// Reads the next character from input and advances the position.
    fn readChar(self: *Lexer) void {
        if (self.read_position >= self.input.len) {
            self.ch = 0;
        } else {
            self.ch = self.input[self.read_position];
        }
        self.position = self.read_position;
        self.read_position += 1;
    }

    /// Identifies and returns the next token in the string.
    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespace();

        var tok = Token{ .type = .ILLEGAL, .literal = "" };

        switch (self.ch) {
            '=' => tok = Token{ .type = .EQUALS, .literal = "=" },
            ';' => tok = Token{ .type = .SEMICOLON, .literal = ";" },
            '"' => {
                const literal = self.readString();
                return Token{ .type = .STRING, .literal = literal };
            },
            0 => tok = Token{ .type = .EOF, .literal = "" },
            else => {
                if (isLetter(self.ch)) {
                    const literal = self.readIdentifier();
                    return Token{ .type = lookupIdentifier(literal), .literal = literal };
                } else if (std.ascii.isDigit(self.ch)) {
                    const literal = self.readNumber();
                    return Token{ .type = .NUMBER, .literal = literal };
                } else {
                    tok = Token{ .type = .ILLEGAL, .literal = self.input[self.position .. self.position + 1] };
                }
            },
        }

        self.readChar();
        return tok;
    }

    /// Reads a continuous string of letters/numbers (key or command).
    fn readIdentifier(self: *Lexer) []const u8 {
        const start = self.position;
        while (isLetter(self.ch) or std.ascii.isDigit(self.ch)) {
            self.readChar();
        }
        return self.input[start..self.position];
    }

    /// Reads a series of digits.
    fn readNumber(self: *Lexer) []const u8 {
        const start = self.position;
        while (std.ascii.isDigit(self.ch)) {
            self.readChar();
        }
        return self.input[start..self.position];
    }

    /// Reads text inside double quotes.
    fn readString(self: *Lexer) []const u8 {
        self.readChar();
        const start = self.position;
        while (self.ch != '"' and self.ch != 0) {
            self.readChar();
        }
        const literal = self.input[start..self.position];
        self.readChar();
        return literal;
    }

    /// Skips all whitespace, tabs, and newlines.
    fn skipWhitespace(self: *Lexer) void {
        while (std.ascii.isWhitespace(self.ch)) {
            self.readChar();
        }
    }
};

/// Checks if a character is a valid letter or underscore.
fn isLetter(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

/// Maps an identified word to either a command or a general identifier.
fn lookupIdentifier(ident: []const u8) TokenType {
    if (std.mem.eql(u8, ident, "SET")) return .SET;
    if (std.mem.eql(u8, ident, "GET")) return .GET;
    if (std.mem.eql(u8, ident, "DELETE")) return .DELETE;
    return .IDENTIFIER;
}

test "Lexer: Key-Value commands" {
    const input = "SET user_1 = \"Ivo\"; GET user_1;";
    var l = Lexer.init(input);

    const expected = [_]struct { type: TokenType, literal: []const u8 }{
        .{ .type = .SET, .literal = "SET" },
        .{ .type = .IDENTIFIER, .literal = "user_1" },
        .{ .type = .EQUALS, .literal = "=" },
        .{ .type = .STRING, .literal = "Ivo" },
        .{ .type = .SEMICOLON, .literal = ";" },
        .{ .type = .GET, .literal = "GET" },
        .{ .type = .IDENTIFIER, .literal = "user_1" },
        .{ .type = .SEMICOLON, .literal = ";" },
        .{ .type = .EOF, .literal = "" },
    };

    for (expected) |exp| {
        const tok = l.nextToken();
        try std.testing.expectEqual(exp.type, tok.type);
        try std.testing.expectEqualStrings(exp.literal, tok.literal);
    }
}
