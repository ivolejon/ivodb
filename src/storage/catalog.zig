const std = @import("std");
const Pager = @import("pager.zig").Pager;
const ValueType = @import("../common/mod.zig").types.ValueType;

pub const Catalog = struct {
    pager: *Pager,

    pub fn getTableStart(self: *Catalog, name: []const u8) !?u64 {
        const block = try self.pager.getBlock(0);
        var iter = @import("cell_iter.zig").CellIterator{ .block = block };

        while (iter.next()) |val| {
            // Kolla om detta värde är namnet vi letar efter
            if (val == .text and std.mem.eql(u8, val.text, name)) {
                // Nästa värde i blocket bör vara sidnumret
                if (iter.next()) |page_val| {
                    return @intCast(page_val.number);
                }
            }
        }
        return null; // Hittade inte tabellen
    }

    pub fn registerTable(self: *Catalog, name: []const u8, start_page: u64) !void {
        const block = try self.pager.getBlock(0);
        if (block.getCellCount() == 0) block.initEmpty();

        try block.insertValue(.{ .text = name });
        try block.insertValue(.{ .number = @intCast(start_page) });
        block.isDirty = true;
    }
};
