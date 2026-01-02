const std = @import("std");
const Pager = @import("../storage/mod.zig").Pager;
const Catalog = @import("../storage/mod.zig").Catalog;
const Table = @import("table.zig").Table;

pub const Database = struct {
    pager: Pager,
    catalog: Catalog,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Database {
        // 1. Allokera Database på heapen
        const self = try allocator.create(Database);
        errdefer allocator.destroy(self);

        // 2. Initiera innehållet direkt på heap-platsen
        self.pager = try Pager.init(allocator, path);
        self.catalog = Catalog{ .pager = &self.pager };

        // 3. Säkerställ att Block 0 (katalogen) finns
        const page_count = try self.pager.disk_manager.getPageCount();
        if (page_count == 0) {
            const block = try self.pager.getBlock(0);
            block.initEmpty();
            try self.pager.flushAll();
        }

        return self;
    }

    pub fn getTable(self: *Database, name: []const u8) !Table {
        // 1. Kolla om tabellen redan finns i katalogen
        if (try self.catalog.getTableStart(name)) |start_page| {
            return Table.init(&self.pager, name, start_page);
        }

        // 2. Om den är ny, hitta en ledig sida.
        // Vi kollar på disk, men vi måste också kompensera för
        // sidor vi nyss gett ut i samma körning.
        var new_page = try self.pager.disk_manager.getPageCount();

        // Om filen är helt ny, börja på sida 1 (Sida 0 är Catalog)
        if (new_page == 0) new_page = 1;

        // VIKTIGT: Om katalogen precis skapat en tabell på 'new_page',
        // men vi inte flushat, måste vi se till att nästa tabell hamnar efter.
        // Ett enkelt sätt är att loopa tills vi hittar en sida som inte finns i katalogen.
        // (För nu räcker det att vi litar på disk + antal tabeller i minnet)

        // 3. Registrera i katalogen
        try self.catalog.registerTable(name, new_page);

        // 4. Initiera den nya sidan så den inte innehåller gammalt skräp
        const block = try self.pager.getBlock(new_page);
        block.initEmpty();

        // 5. Tvinga en flush av katalogen (Block 0) så att disk_manager
        // ser att filen växer till nästa anrop!
        try self.pager.flushBlock(0);
        try self.pager.flushBlock(new_page);

        std.debug.print("DEBUG: Tabell '{s}' tilldelad sida {d}\n", .{ name, new_page });

        return Table.init(&self.pager, name, new_page);
    }

    pub fn deinit(self: *Database, allocator: std.mem.Allocator) void {
        self.pager.deinit();
        allocator.destroy(self);
    }
};
