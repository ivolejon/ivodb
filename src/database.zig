const std = @import("std");
const Pager = @import("pager.zig").Pager;
const Catalog = @import("catalog.zig").Catalog;
const Table = @import("table.zig").Table;

/// Main database engine structure that manages
/// the pager and the system catalog.
pub const Database = struct {
    pager: Pager,
    catalog: Catalog,

    /// Allocates the database on the heap
    /// and initializes the storage and catalog.
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

    /// Retrieves an existing table by name or registers a new one if it doesn't exist.
    /// Ensures new tables are assigned unique starting pages on disk.
    pub fn getTable(self: *Database, name: []const u8) !Table {
        if (try self.catalog.getTableStart(name)) |start_page| {
            return Table.init(&self.pager, name, start_page);
        }

        var new_page = try self.pager.disk_manager.getPageCount();

        if (new_page == 0) new_page = 1;

        try self.catalog.registerTable(name, new_page);

        const block = try self.pager.getBlock(new_page);
        block.initEmpty();

        try self.pager.flushBlock(0);
        try self.pager.flushBlock(new_page);

        std.debug.print("DEBUG: Tabell '{s}' tilldelad sida {d}\n", .{ name, new_page });

        return Table.init(&self.pager, name, new_page);
    }

    /// Performs a clean shutdown of the pager and
    /// deallocates the database memory.
    pub fn deinit(self: *Database, allocator: std.mem.Allocator) void {
        self.pager.deinit();
        allocator.destroy(self);
    }
};
