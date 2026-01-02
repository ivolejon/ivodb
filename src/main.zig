const std = @import("std");
const print = std.debug.print;

const storage = @import("storage/mod.zig");
const engine = @import("engine/mod.zig");
const common = @import("common/mod.zig");

const Field = common.types.Field;
const TableIterator = engine.TableIterator;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    const db = try engine.Database.init(allocator, "data.ivodb");
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
