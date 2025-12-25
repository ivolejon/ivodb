const std = @import("std");
const constants = @import("constants.zig");
const ValueType = @import("types.zig").ValueType;
const TypeTag = @import("types.zig").TypeTag;

pub const Block = struct {
    id: u64,
    isDirty: bool,
    data: [constants.BLOCK_SIZE]u8,

    const HEADER_SIZE: u16 = 12;
    const OFFSET_TYPE: usize = 0; // 1 byte
    const OFFSET_CELL_COUNT: usize = 1; // 2 bytes
    const OFFSET_FREE_START: usize = 3; // 2 bytes (där slot-arrayen slutar)
    const OFFSET_FREE_END: usize = 5; // 2 bytes (där data börjar i botten)
    const MAGIC_NUMBER: u8 = 0x42;
    const OFFSET_MAGIC: usize = 7; // 1 byte

    pub fn initEmpty(self: *Block) void {
        @memset(&self.data, 0);
        self.data[OFFSET_MAGIC] = MAGIC_NUMBER;
        self.setCellCount(0);
        self.setFreeEnd(constants.BLOCK_SIZE); // Börja vid 4096
        self.setFreeStart(HEADER_SIZE); // Börja skriva slots efter headern
        self.isDirty = true;
    }

    pub fn getCellCount(self: *Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_CELL_COUNT..][0..2], .little);
    }

    fn setCellCount(self: *Block, count: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_CELL_COUNT..][0..2], count, .little);
    }

    pub fn getFreeEnd(self: *const Block) u16 {
        // Läser byte 5 och 6
        return std.mem.readInt(u16, self.data[OFFSET_FREE_END .. OFFSET_FREE_END + 2], .little);
    }

    fn setFreeEnd(self: *Block, value: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_FREE_END .. OFFSET_FREE_END + 2], value, .little);
    }

    fn getFreeStart(self: *const Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_FREE_START .. OFFSET_FREE_START + 2], .little);
    }

    fn setFreeStart(self: *Block, value: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_FREE_START .. OFFSET_FREE_START + 2], value, .little);
    }

    pub fn isValid(self: *Block) bool {
        return self.data[OFFSET_MAGIC] == MAGIC_NUMBER;
    }

    pub fn insertValue(self: *Block, value: ValueType) !void {
        const current_free_start = self.getFreeStart();
        const current_free_end = self.getFreeEnd();

        // Beräkna storlek baserat på aktivt fält i unionen
        const payload_size: u16 = switch (value) {
            .int32 => 1 + 4, // Tag + i32
            .varchar => |text| @as(u16, @intCast(text.len)) + 2, // Tag + Längd-byte + Text
            .boolean => 1 + 1, // Tag + 1 byte
        };

        if (current_free_end - current_free_start < payload_size + 2) {
            return error.NoSpaceInBlock;
        }

        const new_free_end = current_free_end - payload_size;

        // Skriv taggen först
        self.data[new_free_end] = @intFromEnum(std.meta.activeTag(value));

        // Skriv data baserat på typ
        switch (value) {
            .int32 => |val| {
                std.mem.writeInt(i32, self.data[new_free_end + 1 ..][0..4], val, .little);
            },
            .varchar => |text| {
                self.data[new_free_end + 1] = @intCast(text.len);
                @memcpy(self.data[new_free_end + 2 ..][0..text.len], text);
            },
            .boolean => |b| {
                self.data[new_free_end + 1] = if (b) @as(u8, 1) else 0;
            },
        }

        // Uppdatera slots och header (precis som förut)
        const slot_pos = current_free_start;
        std.mem.writeInt(u16, self.data[slot_pos..][0..2], new_free_end, .little);

        self.setCellCount(self.getCellCount() + 1);
        self.setFreeStart(current_free_start + 2);
        self.setFreeEnd(new_free_end);
        self.isDirty = true;
    }

    pub fn getValue(self: *Block, index: u16) !ValueType {
        if (index >= self.getCellCount()) return error.IndexOutOfBounds;

        const slot_pos = HEADER_SIZE + (index * 2);
        const offset = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);

        const raw_tag = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, raw_tag) catch return error.UnknownTypeTag;

        return switch (tag) {
            .int32 => {
                const val = std.mem.readInt(i32, self.data[offset + 1 ..][0..4], .little);
                return ValueType{ .int32 = val };
            },
            .varchar => {
                const len = self.data[offset + 1];
                const text = self.data[offset + 2 .. offset + 2 + len];
                return ValueType{ .varchar = text };
            },
            .boolean => {
                return ValueType{ .boolean = self.data[offset + 1] == 1 };
            },
        };
    }

    // pub fn getVarchar(self: *Block, index: u16) ![]const u8 {
    //     const count = self.getCellCount();
    //     if (index >= count) return error.IndexOutOfBounds;

    //     // 1. Beräkna var slot-pekaren för detta index finns
    //     // Slots börjar efter headern (byte 12) och är 2 bytes var
    //     const slot_pos = HEADER_SIZE + (index * 2);

    //     // 2. Läs offseten (var raden faktiskt börjar i data-arrayen)
    //     const record_offset = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);

    //     // 3. Läs längden på varcharen (första byten vid den offseten)
    //     const text_len = self.data[record_offset];

    //     // 4. Returnera en slice till texten (hoppa över längd-byten)
    //     const start = record_offset + 1;
    //     const end = start + text_len;

    //     return self.data[start..end];
    // }
};
