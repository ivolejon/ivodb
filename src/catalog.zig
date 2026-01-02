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
