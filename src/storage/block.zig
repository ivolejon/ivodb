const std = @import("std");
const common = @import("../common/mod.zig");
const constants = common.constants;
const types = common.types;
const ValueType = types.ValueType;
const TypeTag = types.TypeTag;
const CellIterator = @import("cell_iter.zig").Iterator;

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

    pub fn iterator(self: *const Block) CellIterator {
        return CellIterator{
            .block = self,
        };
    }

    pub fn getCellCount(self: *const Block) u16 {
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

    fn getCellSize(self: *const Block, offset: u16) !u16 {
        const tag_byte = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, tag_byte) catch return error.UnknownTypeTag;

        return switch (tag) {
            .int => 1 + 4,
            .varchar => 1 + 1 + @as(u16, self.data[offset + 1]),
            .boolean => 1 + 1,
        };
    }

    pub fn insertValue(self: *Block, value: ValueType) !void {
        const current_free_start = self.getFreeStart();
        const current_free_end = self.getFreeEnd();

        // Beräkna storlek baserat på aktivt fält i unionen
        const payload_size: u16 = switch (value) {
            .int => 1 + 4, // Tag + i32
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
            .int => |val| {
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

        // Uppdatera slots och header
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

        const raw_tag = self.data[offset];
        const tag = std.meta.intToEnum(TypeTag, raw_tag) catch return error.UnknownTypeTag;

        return switch (tag) {
            .int => {
                const val = std.mem.readInt(i32, self.data[offset + 1 ..][0..4], .little);
                return ValueType{ .int = val };
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
    pub fn deleteValue(self: *Block, index: u16) !void {
        const count = self.getCellCount();
        if (index >= count) return error.IndexOutOfBounds;

        // Hitta den rad vi ska ta bort
        const slot_pos = HEADER_SIZE + (index * 2);
        const offset_to_delete = std.mem.readInt(u16, self.data[slot_pos..][0..2], .little);

        // Vi behöver veta storleken på det vi tar bort för att kunna flytta resten
        // Här använder vi en hjälpmetod (se nedan)
        const size_to_delete = try self.getCellSize(offset_to_delete);

        // Flytta all data som ligger "under" (lägre offset) den raderade raden
        // I ett slotted page-block ligger nyare rader på lägre offsets.
        // Vi flyttar data från FreeEnd fram till offset_to_delete.
        const current_free_end = self.getFreeEnd();
        const bytes_to_move = offset_to_delete - current_free_end;

        if (bytes_to_move > 0) {
            // Flytta datan "nedåt" (mot högre adresser) för att täppa till hålet
            std.mem.copyBackwards(u8, self.data[current_free_end + size_to_delete .. offset_to_delete + size_to_delete], self.data[current_free_end..offset_to_delete]);
        }

        // Uppdatera alla ANDRA slots som påverkades av flytten
        // Alla rader som hade en offset lägre än den vi tog bort har nu flyttats framåt.
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const s_pos = HEADER_SIZE + (i * 2);
            const s_offset = std.mem.readInt(u16, self.data[s_pos..][0..2], .little);
            if (s_offset != 0 and s_offset < offset_to_delete) {
                std.mem.writeInt(u16, self.data[s_pos..][0..2], s_offset + size_to_delete, .little);
            }
        }

        // 4. Markera den borttagna sloten som tom (0)
        std.mem.writeInt(u16, self.data[slot_pos..][0..2], 0, .little);

        // 5. Uppdatera FreeEnd
        self.setFreeEnd(current_free_end + size_to_delete);
        self.isDirty = true;
    }

    pub fn hasSpaceFor(self: *const Block, value: ValueType) bool {
        // 1. Beräkna hur mycket plats datan tar
        const data_size = self.getValueSize(value);

        // 2. Beräkna totalt behov:
        // + data_size (själva värdet)
        // + 1 byte (för TypeTag/Header i cellen)
        // + 2 bytes (för den nya slot-pekaren i början av blocket)
        const total_needed = data_size + 1 + 2;

        // 3. Kolla tillgängligt utrymme mellan slots och data
        const current_free_space = self.getFreeEnd() - self.getFreeStart();

        return current_free_space >= total_needed;
    }

    // Hjälpfunktion för att veta storleken på olika typer
    fn getValueSize(self: *const Block, value: ValueType) u16 {
        _ = self;
        return switch (value) {
            .int => 8, // i64
            .boolean => 1, // bool
            .varchar => |s| @as(u16, @intCast(s.len)),
        };
    }
};
