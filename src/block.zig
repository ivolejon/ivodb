const std = @import("std");

const constants = @import("constants.zig");
const types = @import("types.zig");
const ValueType = types.ValueType;
const TypeTag = types.TypeTag;
const CellIterator = @import("cell_iter.zig").CellIterator;

/// Represents a fixed-size data block using a slotted page architecture.
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

    pub fn initEmpty(self: *Block) void {
        @memset(&self.data, 0);
        self.data[OFFSET_MAGIC] = MAGIC_NUMBER;
        self.setCellCount(0);
        self.setFreeEnd(constants.BLOCK_SIZE);
        self.setFreeStart(HEADER_SIZE);
        self.isDirty = true;
    }

    pub fn iterator(self: *const Block) CellIterator {
        return CellIterator{ .block = self };
    }

    pub fn getCellCount(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_CELL_COUNT..][0..2], .little);
    }

    fn setCellCount(self: *Block, count: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_CELL_COUNT..][0..2], count, .little);
    }

    pub fn getFreeEnd(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_FREE_END .. OFFSET_FREE_END + 2][0..2], .little);
    }

    fn setFreeEnd(self: *Block, value: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_FREE_END .. OFFSET_FREE_END + 2][0..2], value, .little);
    }

    pub fn getFreeStart(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_FREE_START .. OFFSET_FREE_START + 2][0..2], .little);
    }

    fn setFreeStart(self: *Block, value: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_FREE_START .. OFFSET_FREE_START + 2][0..2], value, .little);
    }

    pub fn isValid(self: *Block) bool {
        return self.data[OFFSET_MAGIC] == MAGIC_NUMBER;
    }

    fn getCellSize(self: *const Block, offset: u16) !u16 {
        const tag_byte = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, tag_byte) catch return error.UnknownTypeTag;

        return switch (tag) {
            .number => 1 + 4,
            .text => 1 + 2 + std.mem.readInt(u16, self.data[offset + 1 .. offset + 3][0..2], .little),
            .boolean => 1 + 1,
        };
    }

    pub fn insertValue(self: *Block, value: ValueType) !void {
        const current_free_start = self.getFreeStart();
        const current_free_end = self.getFreeEnd();

        const payload_size: u16 = switch (value) {
            .number => 1 + 4,
            .text => |text| @as(u16, @intCast(text.len)) + 3, // 1 tag + 2 len + data
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
                std.mem.writeInt(u16, self.data[new_free_end + 1 ..][0..2], @as(u16, @intCast(text.len)), .little);
                @memcpy(self.data[new_free_end + 3 ..][0..text.len], text);
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

    pub fn getValue(self: *const Block, index: u16) !ValueType {
        if (index >= self.getCellCount()) return error.IndexOutOfBounds;

        const slot_pos = HEADER_SIZE + (index * 2);
        const offset = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);
        if (offset == 0) return error.UnknownTypeTag;

        const raw_tag = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, raw_tag) catch return error.UnknownTypeTag;

        return switch (tag) {
            .number => {
                const val = std.mem.readInt(i32, self.data[offset + 1 ..][0..4], .little);
                return ValueType{ .number = val };
            },
            .text => {
                const len = std.mem.readInt(u16, self.data[offset + 1 .. offset + 3][0..2], .little);
                const text = self.data[offset + 3 .. offset + 3 + len];
                return ValueType{ .text = text };
            },
            .boolean => {
                return ValueType{ .boolean = self.data[offset + 1] == 1 };
            },
        };
    }

    pub fn deleteValue(self: *Block, index: u16) !void {
        const count = self.getCellCount();
        if (index >= count) return error.IndexOutOfBounds;

        const slot_pos = HEADER_SIZE + (index * 2);
        const offset_to_delete = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);
        if (offset_to_delete == 0) return;

        const size_to_delete = try self.getCellSize(offset_to_delete);
        const current_free_end = self.getFreeEnd();

        if (offset_to_delete > current_free_end) {
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

    pub fn hasSpaceFor(self: *const Block, value: ValueType) bool {
        const data_size = self.getValueSize(value);
        // Vi behöver: data_size + 2 bytes för slotten
        const total_needed = data_size + 2;
        const current_free_space = self.getFreeEnd() - self.getFreeStart();

        return current_free_space >= total_needed;
    }

    fn getValueSize(self: *const Block, value: ValueType) u16 {
        _ = self;
        return switch (value) {
            .number => 1 + 4, // Tag + i32
            .boolean => 1 + 1, // Tag + u8
            .text => |s| 1 + 2 + @as(u16, @intCast(s.len)), // Tag + u16 len + data
        };
    }
};

test "Block: initialization and magic number" {
    var block: Block = undefined;
    block.initEmpty();

    try std.testing.expect(block.isValid());
    try std.testing.expectEqual(@as(u16, 0), block.getCellCount());
    try std.testing.expectEqual(@as(u16, constants.BLOCK_SIZE), block.getFreeEnd());
    try std.testing.expect(block.isDirty);
}

test "Block: insert and retrieve different types" {
    var block: Block = undefined;
    block.initEmpty();

    try block.insertValue(.{ .number = 1234 });
    try block.insertValue(.{ .text = "Zig" });
    try block.insertValue(.{ .boolean = true });

    try std.testing.expectEqual(@as(u16, 3), block.getCellCount());

    const v0 = try block.getValue(0);
    try std.testing.expectEqual(@as(i32, 1234), v0.number);

    const v1 = try block.getValue(1);
    try std.testing.expectEqualStrings("Zig", v1.text);

    const v2 = try block.getValue(2);
    try std.testing.expectEqual(true, v2.boolean);
}

test "Block: delete and compact space" {
    var block: Block = undefined;
    block.initEmpty();

    try block.insertValue(.{ .text = "First" });
    try block.insertValue(.{ .text = "Second" });
    try block.insertValue(.{ .text = "Third" });

    const initial_free_end = block.getFreeEnd();
    try block.deleteValue(1);

    try std.testing.expect(block.getFreeEnd() > initial_free_end);

    const v0 = try block.getValue(0);
    try std.testing.expectEqualStrings("First", v0.text);

    const v2 = try block.getValue(2);
    try std.testing.expectEqualStrings("Third", v2.text);

    try std.testing.expectError(error.UnknownTypeTag, block.getValue(1));
}

test "Block: fill up until NoSpaceInBlock" {
    var block: Block = undefined;
    block.initEmpty();

    // Create a text that takes up almost half of the block.
    // We subtract the header (12) and margin for slots.
    const half_block = (constants.BLOCK_SIZE / 2) - 20;
    const big_text = "A" ** half_block;

    // First insertion (takes ~2000 bytes + 2 bytes slot)
    try block.insertValue(.{ .text = big_text });

    // Second insertion (now about 4000 bytes are used)
    try block.insertValue(.{ .text = big_text });

    // Now there should be very little space left (about 40-80 bytes depending on BLOCK_SIZE)
    // We try to insert a third large text.
    const result = block.insertValue(.{ .text = big_text });
    try std.testing.expectError(error.NoSpaceInBlock, result);
}

test "Block: hasSpaceFor validation" {
    var block: Block = undefined;
    block.initEmpty();

    const value = ValueType{ .text = "Hello" };
    try std.testing.expect(block.hasSpaceFor(value));

    const giant_text = "Z" ** (constants.BLOCK_SIZE - 25);
    _ = block.insertValue(.{ .text = giant_text }) catch {};

    try std.testing.expect(!block.hasSpaceFor(value));
}
