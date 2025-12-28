const std = @import("std");

const common = @import("../common/mod.zig");
const ValueType = common.types.ValueType;
const storage = @import("../storage/mod.zig");
const Block = storage.Block;
const Pager = storage.Pager;
const CellIterator = storage.CellIterator;

pub const Table = struct {
    pager: *Pager,
    name: []const u8,
    // I en riktig DB sparas detta i en "Catalog",
    // men vi kan börja med att anta att tabellen startar på page 0.
    first_page_id: u64 = 0,
    total_pages: u64,

    pub fn init(pager: *Pager, name: []const u8) !Table {
        // För tillfället antar vi att vi vet hur många sidor som finns,
        // eller så räknar vi dem i filen.
        return Table{
            .pager = pager,
            .name = name,
            .total_pages = 1, // Börja med minst en sida
        };
    }

    pub fn insert(self: *Table, value: ValueType) !void {
        var page_id = self.total_pages - 1;
        var block = try self.pager.getBlock(page_id);

        // Om det inte finns plats, hämta nästa sida
        if (!block.hasSpaceFor(value)) {
            page_id += 1;
            block = try self.pager.getBlock(page_id);

            // Om det är en helt ny sida, initiera den
            if (block.getCellCount() == 0) {
                block.initEmpty();
            }

            // Uppdatera tabellens storlek
            if (page_id >= self.total_pages) {
                self.total_pages = page_id + 1;
            }
        }

        try block.insertValue(value);
        block.isDirty = true;
    }
};

pub const TableIterator = struct {
    table: *Table,
    current_page_id: u64 = 0,
    cell_iterator: ?CellIterator = null,

    pub fn next(self: *TableIterator) !?ValueType {
        while (self.current_page_id < self.table.total_pages) {
            // Om vi inte har en cell-iterator för nuvarande block, hämta blocket
            if (self.cell_iterator == null) {
                const block = try self.table.pager.getBlock(self.current_page_id);
                self.cell_iterator = .{ .block = block };
            }

            // Försök hämta nästa rad i nuvarande block
            if (self.cell_iterator.?.next()) |val| {
                return val;
            }

            // Blocket är slut, gå till nästa block
            self.current_page_id += 1;
            self.cell_iterator = null;
        }

        return null; // Hela tabellen är genomläst
    }
};
