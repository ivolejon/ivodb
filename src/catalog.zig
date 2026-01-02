const std = @import("std");

const Pager = @import("pager.zig").Pager;
const ValueType = @import("types.zig").ValueType;

/// Manages the mapping between table names and their starting page IDs on disk.
/// The catalog is always stored in Block 0.
pub const Catalog = struct {
    pager: *Pager,

    /// Searches for a table name in the catalog and returns its starting page ID.
    pub fn getTableStart(self: *Catalog, name: []const u8) !?u64 {
        const block = try self.pager.getBlock(0);
        var iter = @import("cell_iter.zig").CellIterator{ .block = block };

        while (iter.next()) |val| {
            if (val == .text and std.mem.eql(u8, val.text, name)) {
                if (iter.next()) |page_val| {
                    return @intCast(page_val.number);
                }
            }
        }
        return null;
    }

    /// Appends a new table entry (name and start page) to the catalog block.
    pub fn registerTable(self: *Catalog, name: []const u8, start_page: u64) !void {
        const block = try self.pager.getBlock(0);
        if (block.getCellCount() == 0) block.initEmpty();

        try block.insertValue(.{ .text = name });
        try block.insertValue(.{ .number = @intCast(start_page) });
        block.isDirty = true;
    }
};

test "Catalog: register and find tables" {
    const allocator = std.testing.allocator;
    const test_file = "test_catalog.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer pager.deinit();

    var catalog = Catalog{ .pager = &pager };

    // 1. Register two different tables
    try catalog.registerTable("users", 1);
    try catalog.registerTable("posts", 5);

    // 2. Find the first table
    const users_page = try catalog.getTableStart("users");
    try std.testing.expect(users_page != null);
    try std.testing.expectEqual(@as(u64, 1), users_page.?);

    // 3. Find the second table
    const posts_page = try catalog.getTableStart("posts");
    try std.testing.expect(posts_page != null);
    try std.testing.expectEqual(@as(u64, 5), posts_page.?);

    // 4. Search for a table that does not exist
    const missing_page = try catalog.getTableStart("ghost_table");
    try std.testing.expect(missing_page == null);
}

test "Catalog: persistence" {
    const allocator = std.testing.allocator;
    const test_file = "test_catalog_persist.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Session 1: Save to the catalog
    {
        var pager = try Pager.init(allocator, test_file);
        defer pager.deinit();
        var catalog = Catalog{ .pager = &pager };

        // Important: Block 0 must be initialized
        const block = try pager.getBlock(0);
        block.initEmpty();

        try catalog.registerTable("persistent_table", 42);
        try pager.flushAll();
    }

    // Session 2: Load from disk and find the table
    {
        var pager = try Pager.init(allocator, test_file);
        defer pager.deinit();
        var catalog = Catalog{ .pager = &pager };

        const start_page = try catalog.getTableStart("persistent_table");
        try std.testing.expectEqual(@as(u64, 42), start_page.?);
    }
}
