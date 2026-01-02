const Block = @import("block.zig").Block;
const ValueType = @import("types.zig").ValueType;
const TypeTag = @import("types.zig").TypeTag;

pub const CellIterator = struct {
    block: *const Block,
    current_index: u16 = 0,

    pub fn next(self: *CellIterator) ?ValueType {
        const count = self.block.getCellCount();

        // Loopa tills vi hittar en aktiv cell eller når slutet
        while (self.current_index < count) {
            const idx = self.current_index;
            self.current_index += 1;

            if (self.block.getValue(idx)) |val| {
                return val;
            } else |_| {
                // Logga nåt här!
                continue;
            }
        }

        return null;
    }
};
