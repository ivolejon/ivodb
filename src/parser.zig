const std = @import("std");
const lex = @import("lexer.zig");
const Token = lex.Token;
const TokenType = lex.TokenType;

/// Represents the types of operations our KV store can perform.
pub const CommandType = enum {
    set,
    get,
    delete,
    create,
    use,
};

/// Data structure that holds the parsed command.
/// Table name is now only required for CREATE and USE.
pub const Command = union(CommandType) {
    set: struct { key: []const u8, value: []const u8 },
    get: struct { key: []const u8 },
    delete: struct { key: []const u8 },
    create: struct { table: []const u8 },
    use: struct { table: []const u8 },
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
            .CREATE => try self.parseCreate(),
            .USE => try self.parseUse(),
            else => return error.InvalidCommand,
        };

        // Ensure the command is properly terminated.
        if (self.peek_token.type == .SEMICOLON) {
            self.nextToken();
        }

        return cmd;
    }

    /// Parses: CREATE <table>
    fn parseCreate(self: *Parser) !Command {
        self.nextToken(); // Move to table name
        const table = try self.expectIdentifierOrString();
        return Command{ .create = .{ .table = table } };
    }

    /// Parses: USE <table>
    fn parseUse(self: *Parser) !Command {
        self.nextToken(); // Move to table name
        const table = try self.expectIdentifierOrString();
        return Command{ .use = .{ .table = table } };
    }

    /// Parses: SET <key> = <value> (table is context-dependent)
    fn parseSet(self: *Parser) !Command {
        self.nextToken(); // Move to key
        const key = try self.expectIdentifierOrString();

        if (self.peek_token.type != .EQUALS) return error.ExpectedEquals;
        self.nextToken(); // Move to '='

        self.nextToken(); // Move to value
        const value = try self.expectValue();

        return Command{ .set = .{ .key = key, .value = value } };
    }

    /// Parses: GET <key>
    fn parseGet(self: *Parser) !Command {
        self.nextToken(); // Move to key
        const key = try self.expectIdentifierOrString();
        return Command{ .get = .{ .key = key } };
    }

    /// Parses: DELETE <key>
    fn parseDelete(self: *Parser) !Command {
        self.nextToken(); // Move to key
        const key = try self.expectIdentifierOrString();
        return Command{ .delete = .{ .key = key } };
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

test "Parser: Full session flow" {
    const input = "CREATE users; USE users; SET ivo = \"dev\"; GET ivo;";
    const l = lex.Lexer.init(input);
    var p = Parser.init(l);

    // 1. Test CREATE
    const cmd1 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd1), .create);
    try std.testing.expectEqualStrings("users", cmd1.create.table);
    p.nextToken();

    // 2. Test USE
    const cmd2 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd2), .use);
    try std.testing.expectEqualStrings("users", cmd2.use.table);
    p.nextToken();

    // 3. Test SET (No table name in command!)
    const cmd3 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd3), .set);
    try std.testing.expectEqualStrings("ivo", cmd3.set.key);
    try std.testing.expectEqualStrings("dev", cmd3.set.value);
    p.nextToken();

    // 4. Test GET
    const cmd4 = try p.parseCommand();
    try std.testing.expectEqual(std.meta.activeTag(cmd4), .get);
    try std.testing.expectEqualStrings("ivo", cmd4.get.key);
}
