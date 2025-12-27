const std = @import("std");
const Block = @import("block.zig").Block;
const DiskManager = @import("disk.zig").DiskManager;
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const constants = @import("../common/constants.zig");
const print = std.debug.print;

pub const Pager = struct {
    disk_manager: DiskManager,
    blocks: HashMap(u64, Block),

    pub fn init(_alloc: Allocator, storage_path: []const u8) !Pager {
        return Pager{
            .disk_manager = try DiskManager.init(storage_path),
            .blocks = HashMap(u64, Block).init(_alloc),
        };
    }

    pub fn deinit(self: *Pager) void {
        self.blocks.deinit();
        self.disk_manager.deinit();
    }

    pub fn getBlock(self: *Pager, page_id: u64) !*Block {
        if (self.blocks.getPtr(page_id)) |cached_block| {
            return cached_block;
        }

        var buffer = [_]u8{0} ** constants.BLOCK_SIZE;
        const bytes_read = try self.disk_manager.readPage(page_id, &buffer);

        try self.blocks.put(page_id, Block{
            .id = page_id,
            .isDirty = false,
            .data = buffer,
        });

        const block = self.blocks.getPtr(page_id).?;

        // Initiera om det är en ny sida
        if (bytes_read == 0 or block.getFreeEnd() == 0) {
            block.initEmpty();
        }

        return block;
    }

    pub fn flushBlock(self: *Pager, page_id: u64) !void {
        const block = self.blocks.getPtr(page_id) orelse return error.BlockNotFound;

        if (!block.isDirty) return;

        try self.disk_manager.writePage(page_id, &block.data);
        block.isDirty = false;
        print("Block {d} flushed to disk\n", .{page_id});
    }

    // Praktisk metod för att spara ALLT vid t.ex. avstängning
    pub fn flushAll(self: *Pager) !void {
        var iter = self.blocks.keyIterator();
        while (iter.next()) |page_id| {
            try self.flushBlock(page_id.*);
        }
    }
};
