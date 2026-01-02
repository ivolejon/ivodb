const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const executor = @import("executor.zig");
const Database = @import("database.zig").Database;
const IoContext = @import("io_context.zig").IoContext;

pub fn main() !void {
    // 1. Setup Memory
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // 2. Database & Executor Setup
    const db_path = "data.ivodb";
    var db = try Database.init(allocator, db_path);
    defer db.deinit(allocator);

    // var exec = executor.Executor.init(db);

    // 3. I/O Setup
    var io_context = IoContext.init();

    try io_context.print("--- Welcome to IvoDB (Zig 0.15) ---\n", .{});
    try io_context.print("Commands: CREATE <table>; USE <table>; SET <k> = <v>;\n", .{});

    // while (true) {
    //     // Prompt
    //     if (exec.active_table) |t| {
    //         try out_stream.print("{s}> ", .{t});
    //     } else {
    //         try out_stream.print("ivodb> ", .{});
    //     }

    //     // in_stream.read

    //     // Läs input med det nya mönstret
    //     const input = (try in_stream.streamDelimiterLimit(&buffer, '\n')) orelse break;

    //     const trimmed = std.mem.trim(u8, input, " \r\n\t");
    //     if (trimmed.len == 0) continue;
    //     if (std.mem.eql(u8, trimmed, "exit")) break;

    //     // 4. Run Logic
    //     const l = lexer.Lexer.init(trimmed);
    //     var p = parser.Parser.init(l);

    //     const cmd = p.parseCommand() catch |err| {
    //         try out_stream.print("Syntax Error: {any}\n", .{err});
    //         continue;
    //     };

    //     exec.execute(cmd) catch |err| {
    //         try out_stream.print("Runtime Error: {any}\n", .{err});
    //     };
    // }
}
