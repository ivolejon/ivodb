const Block = @import("block.zig").Block;
const types = @import("../common/types.zig");
const ValueType = types.ValueType;
const TypeTag = types.TypeTag;

pub const Iterator = struct {
    block: *Block,
    current_index: u16 = 0,

    pub fn next(self: *Iterator) ?ValueType {
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
