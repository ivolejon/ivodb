const std = @import("std");
const print = std.debug.print;

const storage = @import("storage/mod.zig");
const Pager = storage.Pager;

const engine = @import("engine/mod.zig");
const Table = engine.Table;
const TableIterator = engine.TableIterator;

// Vi behöver importera Field för att kunna skapa dokument
const common = @import("common/mod.zig");
const Field = common.types.Field;

pub fn main() !void {
    // Vi använder en ArenaAllocator för att enkelt städa upp
    // de strängar som skapas när vi läser tillbaka dokumenten.
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    var pager = try storage.Pager.init(allocator, "data.ivodb");
    defer pager.deinit();

    var table = try Table.init(&pager, "users2");

    // 1. Skapa och sätt in ett dokument
    print("--- Skriver dokument ---\n", .{});

    const doc1 = &[_]Field{
        .{ .name = "id", .value = .{ .number = 101 } },
        .{ .name = "msg", .value = .{ .text = "Zig is fast" } },
        .{ .name = "ok", .value = .{ .boolean = true } },
    };

    const doc2 = &[_]Field{
        .{ .name = "id", .value = .{ .number = 202 } },
        .{ .name = "msg", .value = .{ .text = "Slotted pages are cool" } },
    };

    try table.insertDocument(doc1);
    try table.insertDocument(doc2);

    // 2. Läs tillbaka dokumenten
    print("\n--- Läser data via nextDocument ---\n", .{});

    var iter = TableIterator{ .table = &table };

    // Vi loopar så länge nextDocument returnerar något
    while (try iter.nextDocument(allocator)) |fields| {
        print("Dokument: {{ ", .{});
        for (fields, 0..) |field, i| {
            print("\"{s}\": ", .{field.name});
            switch (field.value) {
                .number => |n| print("{d}", .{n}),
                .text => |t| print("\"{s}\"", .{t}),
                .boolean => |b| print("{}", .{b}),
            }
            if (i < fields.len - 1) print(", ", .{});
        }
        print(" }}\n", .{});
    }

    try pager.flushAll();
    print("\nAllt sparat till db!\n", .{});
}
