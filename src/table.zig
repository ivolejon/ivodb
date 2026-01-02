const std = @import("std");

const ValueType = @import("types.zig").ValueType;
const Field = @import("types.zig").Field;
const Block = @import("block.zig").Block;
const Pager = @import("pager.zig").Pager;

/// Represents a database table and manages document insertion logic.
pub const Table = struct {
    pager: *Pager,
    name: []const u8,
    first_page_id: u64,
    total_pages: u64,

    /// Initializes a table instance with its assigned starting page on disk.
    pub fn init(pager: *Pager, name: []const u8, start_page: u64) !Table {
        return Table{
            .pager = pager,
            .name = name,
            .first_page_id = start_page,
            .total_pages = 1,
        };
    }

    /// Appends a new document to the table,
    /// allocating and initializing new pages as needed.
    pub fn insertDocument(self: *Table, fields: []const Field) !void {
        var current_page_id = self.first_page_id + (self.total_pages - 1);
        var block = try self.pager.getBlock(current_page_id);

        if (block.getFreeEnd() - block.getFreeStart() < 256) {
            self.total_pages += 1;
            current_page_id = self.first_page_id + (self.total_pages - 1);
            block = try self.pager.getBlock(current_page_id);
            block.initEmpty();
        }

        try block.insertValue(.{ .number = @intCast(fields.len) });
        for (fields) |field| {
            try block.insertValue(.{ .text = field.name });
            try block.insertValue(field.value);
        }
        block.isDirty = true;
    }

    /// Returns a specific block belonging to this table by its relative index.
    pub fn getBlock(self: *Table, relative_page_id: u64) !*Block {
        if (relative_page_id >= self.total_pages) return error.PageNotFound;
        return try self.pager.getBlock(self.first_page_id + relative_page_id);
    }

    /// Helper to insert a single KV pair using the document logic.
    pub fn insertKeyValuePair(self: *Table, key: []const u8, value: []const u8) !void {
        const fields = [_]Field{
            .{ .name = "k", .value = .{ .text = key } },
            .{ .name = "v", .value = .{ .text = value } },
        };
        try self.insertDocument(&fields);
    }
};

test "Table: insert and retrieve document" {
    const allocator = std.testing.allocator;
    const test_file = "test_table_insert.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer pager.deinit();

    // Initialize a table at page 1 (page 0 is the catalog)
    var table = try Table.init(&pager, "users", 1);

    const fields = [_]Field{
        .{ .name = "username", .value = .{ .text = "ivo" } },
        .{ .name = "active", .value = .{ .boolean = true } },
    };

    try table.insertDocument(&fields);

    // Verify that data exists in the block
    const block = try pager.getBlock(1);

    // Header (number of fields)
    const header = try block.getValue(0);
    try std.testing.expectEqual(@as(i32, 2), header.number);

    // First field name
    const f1_name = try block.getValue(1);
    try std.testing.expectEqualStrings("username", f1_name.text);
}

test "Table: page splitting" {
    const allocator = std.testing.allocator;
    const test_file = "test_table_split.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer pager.deinit();

    var table = try Table.init(&pager, "logs", 1);

    // Create a large document (or many small ones) to fill a page.
    // We know that a page is 4096 bytes and your code triggers a split when < 256 bytes remain.
    const long_string = "a" ** 100;
    const fields = [_]Field{
        .{ .name = "data", .value = .{ .text = long_string } },
    };

    // Insert until we force a new page
    var count: u32 = 0;
    while (table.total_pages == 1) : (count += 1) {
        try table.insertDocument(&fields);
    }

    // Verify that total_pages has increased
    try std.testing.expect(table.total_pages > 1);

    // Verify that the new page (page 2) has been initialized
    const block2 = try pager.getBlock(2);
    try std.testing.expect(block2.isValid());
}
