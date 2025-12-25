const std = @import("std");
const constants = @import("constants.zig");

pub const Block = struct {
    id: u64,
    isDirty: bool,
    data: [constants.BLOCK_SIZE]u8,

    const HEADER_SIZE: u16 = 12;
    const OFFSET_TYPE: usize = 0; // 1 byte
    const OFFSET_CELL_COUNT: usize = 1; // 2 bytes
    const OFFSET_FREE_START: usize = 3; // 2 bytes (där slot-arrayen slutar)
    const OFFSET_FREE_END: usize = 5; // 2 bytes (där data börjar i botten)

    pub fn initEmpty(self: *Block) void {
        @memset(&self.data, 0);
        self.setCellCount(0);
        self.setFreeEnd(constants.BLOCK_SIZE); // Börja vid 4096
        self.setFreeStart(HEADER_SIZE); // Börja skriva slots efter headern
        self.isDirty = true;
    }

    pub fn getCellCount(self: *Block) u16 {
        return std.mem.readInt(u16, self.data[OFFSET_CELL_COUNT .. OFFSET_CELL_COUNT + 2], .little);
    }

    fn setCellCount(self: *Block, count: u16) void {
        std.mem.writeInt(u16, self.data[OFFSET_CELL_COUNT .. OFFSET_CELL_COUNT + 2], count, .little);
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

    pub fn insertVarchar(self: *Block, text: []const u8) !void {
        const payload_size = @as(u16, @intCast(text.len)) + 1; // 1 byte för längd + texten
        const current_free_start = self.getFreeStart();
        const current_free_end = self.getFreeEnd();

        // Kolla om data + den nya slot-pekaren (2 bytes) får plats
        if (current_free_end - current_free_start < payload_size + 2) {
            return error.NoSpaceInBlock;
        }

        // 1. Beräkna ny position i botten och skriv datan
        const new_free_end = current_free_end - payload_size;
        self.data[new_free_end] = @as(u8, @intCast(text.len)); // Längd-prefix
        @memcpy(self.data[new_free_end + 1 .. new_free_end + 1 + text.len], text);

        // 2. Skriv slot-pekaren (offseten) i början av ledigt utrymme
        const slot_slice = self.data[current_free_start .. current_free_start + 2];
        std.mem.writeInt(u16, slot_slice[0..2], new_free_end, .little);

        // 3. Uppdatera headern
        self.setCellCount(self.getCellCount() + 1);
        self.setFreeStart(current_free_start + 2); // Nästa slot hamnar 2 bytes framåt
        self.setFreeEnd(new_free_end); // Nästa data hamnar lägre ner
        self.isDirty = true;
    }
};
