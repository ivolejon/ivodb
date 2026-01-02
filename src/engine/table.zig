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

    pub fn insertDocument(self: *Table, fields: []const Field) !void {
        var page_id = self.total_pages - 1;
        var block = try self.pager.getBlock(page_id);

        // Enkel kontroll: ryms hela dokumentet?
        // Varje fält behöver plats för: namn-strängen + värdet + headers
        // Vi kollar om det finns ca 256 bytes kvar som en säkerhetsmarginal
        if (block.getFreeEnd() - block.getFreeStart() < 256) {
            page_id += 1;
            block = try self.pager.getBlock(page_id);
            block.initEmpty();
            self.total_pages = page_id + 1;
        }

        // 1. Spara antal fält i detta dokument (viktigt för läsning!)
        try block.insertValue(.{ .number = @intCast(fields.len) });

        // 2. Spara varje fält som ett par av [Namn, Värde]
        for (fields) |field| {
            try block.insertValue(.{ .text = field.name });
            try block.insertValue(field.value);
        }

        block.isDirty = true;
    }
};

pub const TableIterator = struct {
    table: *Table,
    current_page_id: u64 = 0,
    cell_iterator: ?CellIterator = null,

    /// Hämtar nästa råa värde (ValueType) från tabellen
    pub fn next(self: *TableIterator) !?ValueType {
        while (self.current_page_id < self.table.total_pages) {
            if (self.cell_iterator == null) {
                const block = try self.table.pager.getBlock(self.current_page_id);
                self.cell_iterator = CellIterator{ .block = block };
            }

            if (self.cell_iterator.?.next()) |val| {
                return val;
            }

            self.current_page_id += 1;
            self.cell_iterator = null;
        }
        return null;
    }

    /// Hämtar nästa hela dokument ([]Field)
    pub fn nextDocument(self: *TableIterator, allocator: std.mem.Allocator) !?[]Field {
        // 1. Läs "markören" med next() - INTE nextDocument()
        const header = try self.next() orelse return null;

        // Säkerställ att vi faktiskt läste ett nummer
        const num_fields = @as(usize, @intCast(header.number));

        // 2. Allokera minne för fälten
        var fields = try allocator.alloc(Field, num_fields);
        // Om något går fel under inläsningen, städa upp
        errdefer allocator.free(fields);

        // 3. Läs in fält-paren (namn + värde)
        for (0..num_fields) |i| {
            // Hämta namnet (ska vara text)
            const name_val = try self.next() orelse return error.CorruptDocument;
            // Hämta värdet (kan vara vad som helst)
            const data_val = try self.next() orelse return error.CorruptDocument;

            fields[i] = .{
                .name = try allocator.dupe(u8, name_val.text),
                .value = data_val,
            };
        }

        return fields;
    }
};
