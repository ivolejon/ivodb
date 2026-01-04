const std = @import("std");
const Executor = @import("executor.zig").Executor;
const IoContext = @import("io_context.zig").IoContext;
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const Repl = struct {
    executor: Executor = undefined,
    io: IoContext = undefined,

    pub fn init(executor: *Executor, io: *IoContext) Repl {
        return Repl{
            .executor = executor.*,
            .io = io.*,
        };
    }
    pub fn start(self: *Repl) !void {
        var executor = &self.executor;
        var io = &self.io;

        try self.io.print("--- Welcome to IvoDB REPL ---\n", .{});
        try self.io.print("Type 'exit' or 'quit' to leave.\n", .{});
        try io.print("Commands: CREATE <table>; USE <table>; SET <k> = <v>;\n", .{});

        while (true) {
            if (executor.active_table) |t| {
                try io.print("ivodb/{s}> ", .{t});
            } else {
                try io.print("ivodb> ", .{});
            }
            const input = try io.read_line() orelse break;
            if (input.len == 0) continue;

            const l = lexer.Lexer.init(std.mem.trimEnd(u8, input, "\n\r"));
            var p = parser.Parser.init(l);

            const cmd = p.parseCommand() catch |err| {
                try io.print("Syntax Error: {any}\n", .{err});
                continue;
            };

            executor.execute(cmd) catch |err| {
                try io.print("Runtime Error: {any}\n", .{err});
            };

            executor.db.pager.flushAll() catch |err| {
                try io.print("IO Error: {any}\n", .{err});
            };
        }
    }
};
