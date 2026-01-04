const std = @import("std");

const ValueType = @import("types.zig").ValueType;
const Field = @import("types.zig").Field;
const Block = @import("block.zig").Block;
const Pager = @import("pager.zig").Pager;

fn generateHiddenId() [16]u8 { // TODO: change to uuidV7
    var id: [16]u8 = undefined;
    std.crypto.random.bytes(&id);
    return id;
}

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

        // Kontrollera om vi behöver en ny sida
        if (block.getFreeEnd() - block.getFreeStart() < 256) {
            self.total_pages += 1;
            current_page_id = self.first_page_id + (self.total_pages - 1);
            block = try self.pager.getBlock(current_page_id);
            block.initEmpty();
        }


        const hidden_id = generateHiddenId(); // 16byte

        try block.insertValue(.{ .number = @intCast(fields.len + 1) });

        try block.insertValue(.{ .text = "_id" });
        try block.insertValue(.{ .text = &hidden_id });//16

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

test "Table: insert and retrieve document with hidden ID" {
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

    const block = try pager.getBlock(1);

    // Header (number of fields)
    const header = try block.getValue(0);
    try std.testing.expectEqual(@as(i32, 3), header.number);

    
    const id_label = try block.getValue(1);
    try std.testing.expectEqualStrings("_id", id_label.text);

    const id_value = try block.getValue(2);
    try std.testing.expectEqual(@as(usize, 16), id_value.text.len);

    // 3. Kontrollera det första vanliga fältet (username)
    // Offset är nu 3 (header) + 2 (id_label + id_val) = 3
    const f1_name = try block.getValue(3);
    try std.testing.expectEqualStrings("username", f1_name.text);

    const f1_val = try block.getValue(4);
    try std.testing.expectEqualStrings("ivo", f1_val.text);
}

test "Table: page splitting with hidden ID" {
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

    while (table.total_pages == 1) {
        try table.insertDocument(&fields);
    }

    try std.testing.expect(table.total_pages > 1);

    const block2 = try pager.getBlock(2);
    try std.testing.expect(block2.isValid());

    const first_val_page2 = try block2.getValue(0);
    try std.testing.expect(first_val_page2 == .number);
    const id_label_page2 = try block2.getValue(1);
    try std.testing.expectEqualStrings("_id", id_label_page2.text);
}
