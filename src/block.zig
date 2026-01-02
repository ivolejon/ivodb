const std = @import("std");

const constants = @import("constants.zig");
const types = @import("types.zig");
const ValueType = types.ValueType;
const TypeTag = types.TypeTag;
const CellIterator = @import("cell_iter.zig").CellIterator;

/// Represents a fixed-size data block using a slotted page architecture.
/// Slots grow from the top (after header), and data grows from the bottom.
pub const Block = struct {
    id: u64,
    isDirty: bool,
    data: [constants.BLOCK_SIZE]u8,

    const HEADER_SIZE: u16 = 12;
    const OFFSET_TYPE: usize = 0;
    const OFFSET_CELL_COUNT: usize = 1;
    const OFFSET_FREE_START: usize = 3;
    const OFFSET_FREE_END: usize = 5;
    const MAGIC_NUMBER: u8 = 0x42;
    const OFFSET_MAGIC: usize = 7;

    /// Formats the block as an empty slotted page with a valid magic number.
    pub fn initEmpty(self: *Block) void {
        @memset(&self.data, 0);
        self.data[OFFSET_MAGIC] = MAGIC_NUMBER;
        self.setCellCount(0);
        self.setFreeEnd(constants.BLOCK_SIZE);
        self.setFreeStart(HEADER_SIZE);
        self.isDirty = true;
    }

    /// Returns an iterator to traverse all cells stored within this block.
    pub fn iterator(self: *const Block) CellIterator {
        return CellIterator{
            .block = self,
        };
    }

    /// Retrieves the number of occupied slots in the block.
    pub fn getCellCount(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_CELL_COUNT..][0..2], .little);
    }

    fn setCellCount(self: *Block, count: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_CELL_COUNT..][0..2], count, .little);
    }

    /// Returns the offset where the free space ends and data starts.
    pub fn getFreeEnd(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_FREE_END .. OFFSET_FREE_END + 2], .little);
    }

    fn setFreeEnd(self: *Block, value: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_FREE_END .. OFFSET_FREE_END + 2], value, .little);
    }

    /// Returns the offset where free space begins (end of slot array).
    pub fn getFreeStart(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_FREE_START .. OFFSET_FREE_START + 2], .little);
    }

    fn setFreeStart(self: *Block, value: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_FREE_START .. OFFSET_FREE_START + 2], value, .little);
    }

    /// Checks if the block contains the correct magic number.
    pub fn isValid(self: *Block) bool {
        return self.data[OFFSET_MAGIC] == MAGIC_NUMBER;
    }

    fn getCellSize(self: *const Block, offset: u16) !u16 {
        const tag_byte = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, tag_byte) catch return error.UnknownTypeTag;

        return switch (tag) {
            .number => 1 + 4,
            .text => 1 + 1 + @as(u16, self.data[offset + 1]),
            .boolean => 1 + 1,
        };
    }

    /// Inserts a value into the block, updating the slot array and free space pointers.
    pub fn insertValue(self: *Block, value: ValueType) !void {
        const current_free_start = self.getFreeStart();
        const current_free_end = self.getFreeEnd();

        const payload_size: u16 = switch (value) {
            .number => 1 + 4,
            .text => |text| @as(u16, @intCast(text.len)) + 2,
            .boolean => 1 + 1,
        };

        if (current_free_end - current_free_start < payload_size + 2) {
            return error.NoSpaceInBlock;
        }

        const new_free_end = current_free_end - payload_size;

        self.data[new_free_end] = @intFromEnum(std.meta.activeTag(value));

        switch (value) {
            .number => |val| {
                std.mem.writeInt(i32, self.data[new_free_end + 1 ..][0..4], val, .little);
            },
            .text => |text| {
                self.data[new_free_end + 1] = @intCast(text.len);
                @memcpy(self.data[new_free_end + 2 ..][0..text.len], text);
            },
            .boolean => |b| {
                self.data[new_free_end + 1] = if (b) @as(u8, 1) else 0;
            },
        }

        const slot_pos = current_free_start;
        std.mem.writeInt(u16, self.data[slot_pos..][0..2], new_free_end, .little);

        self.setCellCount(self.getCellCount() + 1);
        self.setFreeStart(current_free_start + 2);
        self.setFreeEnd(new_free_end);
        self.isDirty = true;
    }

    /// Retrieves a value by its index in the slot array.
    pub fn getValue(self: *const Block, index: u16) !ValueType {
        if (index >= self.getCellCount()) return error.IndexOutOfBounds;

        const slot_pos = HEADER_SIZE + (index * 2);
        const offset = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);

        const raw_tag = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, raw_tag) catch return error.UnknownTypeTag;

        return switch (tag) {
            .number => {
                const val = std.mem.readInt(i32, self.data[offset + 1 ..][0..4], .little);
                return ValueType{ .number = val };
            },
            .text => {
                const len = self.data[offset + 1];
                const text = self.data[offset + 2 .. offset + 2 + len];
                return ValueType{ .text = text };
            },
            .boolean => {
                return ValueType{ .boolean = self.data[offset + 1] == 1 };
            },
        };
    }

    /// Removes a value and compacts the data to reclaim space.
    pub fn deleteValue(self: *Block, index: u16) !void {
        const count = self.getCellCount();
        if (index >= count) return error.IndexOutOfBounds;

        const slot_pos = HEADER_SIZE + (index * 2);
        const offset_to_delete = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);

        const size_to_delete = try self.getCellSize(offset_to_delete);

        const current_free_end = self.getFreeEnd();
        const bytes_to_move = offset_to_delete - current_free_end;

        if (bytes_to_move > 0) {
            std.mem.copyBackwards(u8, self.data[current_free_end + size_to_delete .. offset_to_delete + size_to_delete], self.data[current_free_end..offset_to_delete]);
        }

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const s_pos = HEADER_SIZE + (i * 2);
            const s_offset = std.mem.readInt(u16, self.data[s_pos..][0..2], .little);
            if (s_offset != 0 and s_offset < offset_to_delete) {
                std.mem.writeInt(u16, self.data[s_pos..][0..2], s_offset + size_to_delete, .little);
            }
        }

        std.mem.writeInt(u16, self.data[slot_pos..][0..2], 0, .little);

        self.setFreeEnd(current_free_end + size_to_delete);
        self.isDirty = true;
    }

    /// Checks if the block has sufficient space to store the given value.
    pub fn hasSpaceFor(self: *const Block, value: ValueType) bool {
        const data_size = self.getValueSize(value);
        const total_needed = data_size + 1 + 2;
        const current_free_space = self.getFreeEnd() - self.getFreeStart();

        return current_free_space >= total_needed;
    }

    fn getValueSize(self: *const Block, value: ValueType) u16 {
        _ = self;
        return switch (value) {
            .number => 8,
            .boolean => 1,
            .text => |s| @as(u16, @intCast(s.len)),
        };
    }
};
