const std = @import("std");

const common = @import("../common/mod.zig");
const ValueType = common.types.ValueType;
const Field = common.types.Field;
const storage = @import("../storage/mod.zig");
const Block = storage.Block;
const Pager = storage.Pager;
const CellIterator = storage.CellIterator;

pub const Table = struct {
    pager: *Pager,
    name: []const u8,
    // Sätts nu dynamiskt via Catalog/Database
    first_page_id: u64,
    total_pages: u64,

    pub fn init(pager: *Pager, name: []const u8, start_page: u64) !Table {
        return Table{
            .pager = pager,
            .name = name,
            .first_page_id = start_page,
            .total_pages = 1,
        };
    }

    pub fn insertDocument(self: *Table, fields: []const Field) !void {
        // Här låg felet förut: Vi måste räkna från first_page_id!
        var current_page_id = self.first_page_id + (self.total_pages - 1);
        var block = try self.pager.getBlock(current_page_id);

        // Om sidan är full, skapa en ny
        if (block.getFreeEnd() - block.getFreeStart() < 256) {
            self.total_pages += 1;
            current_page_id = self.first_page_id + (self.total_pages - 1);
            block = try self.pager.getBlock(current_page_id);
            block.initEmpty();
        }

        // Skriv datan...
        try block.insertValue(.{ .number = @intCast(fields.len) });
        for (fields) |field| {
            try block.insertValue(.{ .text = field.name });
            try block.insertValue(field.value);
        }
        block.isDirty = true;
    }
};
