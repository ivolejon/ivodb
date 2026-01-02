const std = @import("std");
const Pager = @import("pager.zig").Pager;
const Catalog = @import("catalog.zig").Catalog;
const Table = @import("table.zig").Table;

/// Main database engine structure that manages the pager and the system catalog.
pub const Database = struct {
    pager: Pager,
    catalog: Catalog,

    /// Allocates the database on the heap and initializes the storage and catalog.
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Database {
        const self = try allocator.create(Database);
        errdefer allocator.destroy(self);

        self.pager = try Pager.init(allocator, path);
        self.catalog = Catalog{ .pager = &self.pager };

        const page_count = try self.pager.disk_manager.getPageCount();
        if (page_count == 0) {
            const block = try self.pager.getBlock(0);
            block.initEmpty();
            try self.pager.flushAll();
        }

        return self;
    }

    /// Explicitly creates a new table. Returns error if table already exists.
    pub fn createTable(self: *Database, name: []const u8) !Table {
        // Check if it already exists
        if (try self.catalog.getTableStart(name)) |_| {
            return error.TableAlreadyExists;
        }

        // Find next available page
        var new_page = try self.pager.disk_manager.getPageCount();
        if (new_page == 0) new_page = 1;

        // Register and initialize the first page for the table
        try self.catalog.registerTable(name, new_page);

        const block = try self.pager.getBlock(new_page);
        block.initEmpty();

        // Flush to ensure the new table is persisted
        try self.pager.flushBlock(0);
        try self.pager.flushBlock(new_page);

        std.debug.print("DEBUG: Table '{s}' created at page {d}\n", .{ name, new_page });

        return Table.init(&self.pager, name, new_page);
    }

    /// Opens an existing table. Returns error if table is not found.
    pub fn getTable(self: *Database, name: []const u8) !Table {
        if (try self.catalog.getTableStart(name)) |start_page| {
            return Table.init(&self.pager, name, start_page);
        }
        return error.TableNotFound;
    }

    /// Performs a clean shutdown of the pager and deallocates the database memory.
    pub fn deinit(self: *Database, allocator: std.mem.Allocator) void {
        self.pager.deinit();
        allocator.destroy(self);
    }
};

test "Database init and deinit" {
    const allocator = std.testing.allocator;

    const db = try Database.init(allocator, "test_data.ivodb");
    defer db.deinit(allocator);

    try db.pager.flushAll();
    _ = try std.fs.cwd().deleteFile("test_data.ivodb");
}

test "Create and retrieve table" {
    const allocator = std.testing.allocator;

    const db = try Database.init(allocator, "test_data.ivodb");
    defer db.deinit(allocator);

    const table_name = "test_table";

    // Create table
    const table = try db.createTable(table_name);
    std.debug.print("Created table '{s}' at page {d}\n", .{ table_name, table.first_page_id });

    // Retrieve the same table
    const retrieved_table = try db.getTable(table_name);
    std.debug.print("Retrieved table '{s}' at page {d}\n", .{ table_name, retrieved_table.first_page_id });

    try db.pager.flushAll();
    _ = try std.fs.cwd().deleteFile("test_data.ivodb");
}

test "Can not use table before create" {
    const allocator = std.testing.allocator;

    const db = try Database.init(allocator, "test_data.ivodb");
    defer db.deinit(allocator);

    const table_name = "non_existent_table";

    const result = db.getTable(table_name);
    try std.testing.expectError(error.TableNotFound, result);

    try db.pager.flushAll();
    _ = try std.fs.cwd().deleteFile("test_data.ivodb");
}
