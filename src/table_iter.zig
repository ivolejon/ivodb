const std = @import("std");
const Table = @import("table.zig").Table;
const CellIterator = @import("cell_iter.zig").CellIterator;
const ValueType = @import("types.zig").ValueType;
const Field = @import("types.zig").Field;
const Allocator = std.mem.Allocator;

/// An iterator that scans through a table's pages to retrieve raw values or full documents.
pub const TableIterator = struct {
    table: *Table,
    relative_page_id: u64 = 0,
    cell_iterator: ?CellIterator = null,

    /// Retrieves the next raw ValueType from the table by traversing pages and cells.
    pub fn next(self: *TableIterator) !?ValueType {
        while (self.relative_page_id < self.table.total_pages) {
            if (self.cell_iterator == null) {
                const absolute_id = self.table.first_page_id + self.relative_page_id;

                const total_disk_pages = try self.table.pager.disk_manager.getPageCount();
                if (absolute_id >= total_disk_pages) return null;

                const block = try self.table.pager.getBlock(absolute_id);

                self.cell_iterator = CellIterator{ .block = block };
            }

            if (self.cell_iterator.?.next()) |val| {
                return val;
            }

            self.relative_page_id += 1;
            self.cell_iterator = null;
        }
        return null;
    }

    /// Reconstructs a complete document from the data stream using the provided allocator.
    /// Expects a numeric header indicating the number of fields in the document.
    pub fn nextDocument(self: *TableIterator, allocator: Allocator) !?[]Field {
        const header = try self.next() orelse return null;

        if (header != .number) return error.InvalidDocumentHeader;
        const num_fields = @as(usize, @intCast(header.number));

        var fields = try allocator.alloc(Field, num_fields);
        errdefer allocator.free(fields);

        for (0..num_fields) |i| {
            const name_val = try self.next() orelse return error.CorruptDocument;

            if (name_val != .text) return error.ExpectedTextFieldName;

            const data_val = try self.next() orelse return error.CorruptDocument;

            fields[i] = .{
                .name = try allocator.dupe(u8, name_val.text),
                .value = data_val,
            };
        }

        return fields;
    }
};

test "TableIterator: iterate raw values" {
    const Pager = @import("pager.zig").Pager;
    const allocator = std.testing.allocator;
    const test_file = "test_iter_raw.ivodb";

    // Clean up old data
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer pager.deinit();

    // 1. Initialize the table.
    // IMPORTANT: Page 0 is the catalog, so we start at page 1.
    var table = try Table.init(&pager, "test", 1);

    // 2. Write data. insertDocument sets block.isDirty = true.
    const fields = [_]Field{
        .{ .name = "id", .value = .{ .number = 100 } },
    };
    try table.insertDocument(&fields);

    // 3. Force data to disk so that getPageCount() sees the pages
    try pager.flushAll();

    // 4. Start the iterator
    var iter = TableIterator{ .table = &table };

    // Now .next() should not return null
    const v1_opt = try iter.next();
    try std.testing.expect(v1_opt != null);
    try std.testing.expectEqual(@as(i32, 1), v1_opt.?.number);

    const v2_opt = try iter.next();
    try std.testing.expect(v2_opt != null);
    try std.testing.expectEqualStrings("id", v2_opt.?.text);

    const v3_opt = try iter.next();
    try std.testing.expect(v3_opt != null);
    try std.testing.expectEqual(@as(i32, 100), v3_opt.?.number);
}

test "TableIterator: nextDocument reconstruction" {
    const Pager = @import("pager.zig").Pager;
    const allocator = std.testing.allocator;
    const test_file = "test_iter_doc.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer pager.deinit();

    var table = try Table.init(&pager, "users", 1);

    const doc1 = [_]Field{
        .{ .name = "name", .value = .{ .text = "Alice" } },
        .{ .name = "age", .value = .{ .number = 30 } },
    };
    try table.insertDocument(&doc1);

    // --- IMPORTANT: Sync the cache with the disk ---
    try pager.flushAll();
    // -----------------------------------------------

    var iter = TableIterator{ .table = &table };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const result = try iter.nextDocument(arena.allocator());

    // Now this will pass!
    try std.testing.expect(result != null);
    const fields = result.?;

    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("name", fields[0].name);
    try std.testing.expectEqualStrings("Alice", fields[0].value.text);
    try std.testing.expectEqualStrings("age", fields[1].name);
    try std.testing.expectEqual(@as(i32, 30), fields[1].value.number);

    try std.testing.expect((try iter.nextDocument(arena.allocator())) == null);
}
