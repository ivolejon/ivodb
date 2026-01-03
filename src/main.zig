const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const executor = @import("executor.zig");
const Database = @import("database.zig").Database;
const IoContext = @import("io_context.zig").IoContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // 2. Database & Executor Setup
    const db_path = "data.ivodb";
    var db = try Database.init(allocator, db_path);
    defer db.deinit(allocator);

    var exec = executor.Executor.init(db);

    // 3. I/O Setup
    var io_context = IoContext.init();

    try io_context.print("--- Welcome to IvoDB ---\n", .{});
    try io_context.print("Commands: CREATE <table>; USE <table>; SET <k> = <v>;\n", .{});

    while (true) {
        // io_context.flush_input();
        if (exec.active_table) |t| {
            try io_context.print("ivodb/{s}> ", .{t});
        } else {
            try io_context.print("ivodb> ", .{});
        }
        const input = try io_context.read_line() orelse break;
        if (input.len == 0) continue;

        const l = lexer.Lexer.init(std.mem.trimEnd(u8, input, "\n\r"));
        var p = parser.Parser.init(l);

        const cmd = p.parseCommand() catch |err| {
            try io_context.print("Syntax Error: {any}\n", .{err});
            continue;
        };

        exec.execute(cmd) catch |err| {
            try io_context.print("Runtime Error: {any}\n", .{err});
        };
    }
}
