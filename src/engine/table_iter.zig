const std = @import("std");
const Table = @import("table.zig").Table;
const storage = @import("../storage/mod.zig");
const CellIterator = storage.CellIterator;
const common = @import("../common/mod.zig");
const ValueType = common.types.ValueType;
const Field = common.types.Field;
const Allocator = std.mem.Allocator;

pub const TableIterator = struct {
    table: *Table,
    relative_page_id: u64 = 0,
    cell_iterator: ?CellIterator = null,

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

            // Sidan slut, gå till nästa RELATIVA sida
            self.relative_page_id += 1;
            self.cell_iterator = null;
        }
        return null;
    }

    pub fn nextDocument(self: *TableIterator, allocator: Allocator) !?[]Field {
        const header = try self.next() orelse return null;

        // union-panics
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
