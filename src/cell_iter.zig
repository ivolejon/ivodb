const Block = @import("block.zig").Block;
const ValueType = @import("types.zig").ValueType;
const TypeTag = @import("types.zig").TypeTag;
const std = @import("std");

/// An iterator designed to traverse individual data cells within a single Block.
pub const CellIterator = struct {
    block: *const Block,
    current_index: u16 = 0,

    /// Retrieves the next valid ValueType from the block's slot array.
    /// Automatically skips over slots that fail to resolve to a value.
    pub fn next(self: *CellIterator) ?ValueType {
        const count = self.block.getCellCount();

        while (self.current_index < count) {
            const idx = self.current_index;
            self.current_index += 1;

            if (self.block.getValue(idx)) |val| {
                return val;
            } else |_| {
                continue;
            }
        }

        return null;
    }
};

test "CellIterator: iterate values in a block" {
    // const allocator = std.testing.allocator;

    // Vi skapar ett block manuellt i minnet för att testa iteratorn
    var block = @import("block.zig").Block{
        .id = 0,
        .isDirty = false,
        .data = [_]u8{0} ** @import("constants.zig").BLOCK_SIZE,
    };
    block.initEmpty();

    // Lägg till några testvärden
    try block.insertValue(.{ .number = 10 });
    try block.insertValue(.{ .text = "hello" });
    try block.insertValue(.{ .boolean = true });

    var iter = CellIterator{ .block = &block };

    // Verifiera första värdet
    const v1 = iter.next();
    try std.testing.expect(v1 != null);
    try std.testing.expectEqual(@as(i32, 10), v1.?.number);

    // Verifiera andra värdet
    const v2 = iter.next();
    try std.testing.expect(v2 != null);
    try std.testing.expectEqualStrings("hello", v2.?.text);

    // Verifiera tredje värdet
    const v3 = iter.next();
    try std.testing.expect(v3 != null);
    try std.testing.expectEqual(true, v3.?.boolean);

    // Slutet på blocket
    try std.testing.expect(iter.next() == null);
}

test "CellIterator: empty block" {
    var block = @import("block.zig").Block{
        .id = 0,
        .isDirty = false,
        .data = [_]u8{0} ** @import("constants.zig").BLOCK_SIZE,
    };
    block.initEmpty();

    var iter = CellIterator{ .block = &block };
    try std.testing.expect(iter.next() == null);
}
