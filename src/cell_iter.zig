const Block = @import("block.zig").Block;
const ValueType = @import("types.zig").ValueType;
const TypeTag = @import("types.zig").TypeTag;

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
