const std = @import("std");
const print = std.debug.print;

const ivodb = @import("ivodb");

const storage = @import("storage/mod.zig");
const Pager = storage.Pager;

const engine = @import("engine/mod.zig");
const Table = engine.Table;
const TableIterator = engine.TableIterator;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var pager = try storage.Pager.init(allocator, "data.ivodb");
    defer pager.deinit();

    //Skapa tabell-objektet
    var table = try Table.init(&pager, "users");

    // 4. Sätt in lite testdata
    std.debug.print("--- Skriver data ---\n", .{});

    try table.insert(.{ .int = 101 });
    try table.insert(.{ .varchar = "Zig is fast" });
    try table.insert(.{ .boolean = true });
    try table.insert(.{ .int = 202 });
    try table.insert(.{ .varchar = "Slotted pages are cool" });

    // 5. Läs tillbaka allt med vår TableIterator
    std.debug.print("\n--- Läser data via TableIterator ---\n", .{});

    var iter = TableIterator{ .table = &table };
    while (try iter.next()) |value| {
        switch (value) {
            .int => |i| std.debug.print("Hittade Int: {d}\n", .{i}),
            .boolean => |b| std.debug.print("Hittade Bool: {}\n", .{b}),
            .varchar => |s| std.debug.print("Hittade Str: {s}\n", .{s}),
        }
    }

    // 6. Spara allt till disk innan vi stänger
    try pager.flushAll();
    std.debug.print("\nAllt sparat till db!\n", .{});
}

test {
    // This ensures nested tests are discovered
    _ = storage;
}
