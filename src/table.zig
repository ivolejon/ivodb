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
};
