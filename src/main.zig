const std = @import("std");
const print = std.debug.print;
const TableIterator = @import("table_iter.zig").TableIterator;
const Field = @import("types.zig").Field;
const Database = @import("database.zig").Database;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    const db = try Database.init(allocator, "data.ivodb");
    defer db.deinit(allocator);

    var users = try db.getTable("users");
    var logs = try db.getTable("system_logs");

    try users.insertDocument(&.{.{ .name = "user", .value = .{ .text = "ivo" } }});
    try logs.insertDocument(&.{.{ .name = "event", .value = .{ .text = "login" } }});

    print("\n--- Innehåll i tabell: USERS ---\n", .{});
    var user_iter = TableIterator{ .table = &users };
    while (try user_iter.nextDocument(allocator)) |fields| {
        printDocument(fields);
    }

    print("\n--- Innehåll i tabell: SYSTEM_LOGS ---\n", .{});
    var log_iter = TableIterator{ .table = &logs };
    while (try log_iter.nextDocument(allocator)) |fields| {
        printDocument(fields);
    }

    try db.pager.flushAll();
    print("\nAll data sparad till disk.\n", .{});
}

// Helper function for printing documents
fn printDocument(fields: []Field) void {
    print("{{ ", .{});
    for (fields, 0..) |f, i| {
        print("\"{s}\": ", .{f.name});
        switch (f.value) {
            .number => |n| print("{d}", .{n}),
            .text => |t| print("\"{s}\"", .{t}),
            .boolean => |b| print("{}", .{b}),
        }
        if (i < fields.len - 1) print(", ", .{});
    }
    print(" }}\n", .{});
}
