const std = @import("std");
const lex = @import("lexer.zig");
const Token = lex.Token;
const TokenType = lex.TokenType;

/// Represents the types of operations our KV store can perform.
pub const CommandType = enum {
    set,
    get,
    delete,
};

/// Data structure that holds the parsed command, target table, and data.
pub const Command = union(CommandType) {
    set: struct { table: []const u8, key: []const u8, value: []const u8 },
    get: struct { table: []const u8, key: []const u8 },
    delete: struct { table: []const u8, key: []const u8 },
};

/// Parser for the Key-Value store grammar.
pub const Parser = struct {
    lexer: lex.Lexer,
    cur_token: Token,
    peek_token: Token,

    /// Initializes the parser by loading the first two tokens from the lexer.
    pub fn init(lexer: lex.Lexer) Parser {
        var p = Parser{
            .lexer = lexer,
            .cur_token = undefined,
            .peek_token = undefined,
        };
        p.nextToken();
        p.nextToken();
        return p;
    }

    /// Advances the parser by one token.
    pub fn nextToken(self: *Parser) void {
        self.cur_token = self.peek_token;
        self.peek_token = self.lexer.nextToken();
    }

    /// Parses a command from the current token stream.
    pub fn parseCommand(self: *Parser) !Command {
        const cmd = switch (self.cur_token.type) {
            .SET => try self.parseSet(),
            .GET => try self.parseGet(),
            .DELETE => try self.parseDelete(),
            else => return error.InvalidCommand,
        };

        // Ensure the command is properly terminated.
        if (self.peek_token.type == .SEMICOLON) {
            self.nextToken();
        }

        return cmd;
    }

    /// Parses a SET command: SET <table> <key> = <value>
    fn parseSet(self: *Parser) !Command {
        self.nextToken(); // Move to table name
        const table = try self.expectIdentifierOrString();

        self.nextToken(); // Move to key
        const key = try self.expectIdentifierOrString();

        if (self.peek_token.type != .EQUALS) return error.ExpectedEquals;
        self.nextToken(); // Move to '='

        self.nextToken(); // Move to value
        const value = try self.expectValue();

        return Command{ .set = .{ .table = table, .key = key, .value = value } };
    }

    // Parses a GET command: GET <table> <key>
    fn parseGet(self: *Parser) !Command {
        self.nextToken(); // Move to table name
        const table = try self.expectIdentifierOrString();

        self.nextToken(); // Move to key
        const key = try self.expectIdentifierOrString();

        return Command{ .get = .{ .table = table, .key = key } };
    }

    /// Parses a DELETE command: DELETE <table> <key>
    fn parseDelete(self: *Parser) !Command {
        self.nextToken(); // Move to table name
        const table = try self.expectIdentifierOrString();

        self.nextToken(); // Move to key
        const key = try self.expectIdentifierOrString();

        return Command{ .delete = .{ .table = table, .key = key } };
    }

    /// Validates and returns an identifier or a string.
    fn expectIdentifierOrString(self: *Parser) ![]const u8 {
        return switch (self.cur_token.type) {
            .IDENTIFIER, .STRING => self.cur_token.literal,
            else => error.ExpectedIdentifierOrString,
        };
    }

    /// Validates and returns an identifier, string, or number as a value.
    fn expectValue(self: *Parser) ![]const u8 {
        return switch (self.cur_token.type) {
            .IDENTIFIER, .STRING, .NUMBER => self.cur_token.literal,
            else => error.ExpectedValue,
        };
    }
};

// --- Tests ---

test "Parser: Parse SET, GET, and DELETE with table names" {
    const input = "SET users ivo = \"dev\"; GET users ivo; DELETE logs old_entry;";
    const l = lex.Lexer.init(input);
    var p = Parser.init(l);

    // Test SET command
    const cmd1 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd1), .set);
    try std.testing.expectEqualStrings("users", cmd1.set.table);
    try std.testing.expectEqualStrings("ivo", cmd1.set.key);
    try std.testing.expectEqualStrings("dev", cmd1.set.value);

    p.nextToken(); // Skip semicolon

    // Test GET command
    const cmd2 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd2), .get);
    try std.testing.expectEqualStrings("users", cmd2.get.table);
    try std.testing.expectEqualStrings("ivo", cmd2.get.key);

    p.nextToken(); // Skip semicolon

    // Test DELETE command
    const cmd3 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd3), .delete);
    try std.testing.expectEqualStrings("logs", cmd3.delete.table);
    try std.testing.expectEqualStrings("old_entry", cmd3.delete.key);
}
