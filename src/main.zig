const std = @import("std");
const executor = @import("executor.zig");
const Database = @import("database.zig").Database;
const IoContext = @import("io_context.zig").IoContext;
const Repl = @import("repl.zig").Repl;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const db_path = "data.ivodb";
    var db = try Database.init(allocator, db_path);
    defer db.deinit(allocator);

    var exec = executor.Executor.init(db);

    var io = IoContext.init();

    try io.print("--- Welcome to IvoDB ---\n", .{});

    var repl = Repl.init(&exec, &io);
    try repl.start();
}
