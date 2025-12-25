const std = @import("std");
const Block = @import("block.zig").Block;
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const constants = @import("../common/constants.zig");
const print = std.debug.print;

pub const Pager = struct {
    data_file: std.fs.File,
    blocks: HashMap(u64, Block),

    pub fn init(_alloc: Allocator, storage_path: []const u8) !Pager {
        const file = try std.fs.cwd().openFile(storage_path, .{ .mode = .read_write });
        const blocks = HashMap(u64, Block).init(_alloc);
        return Pager{
            .data_file = file,
            .blocks = blocks,
        };
    }

    pub fn deinit(self: *Pager) void {
        self.blocks.deinit();
        self.data_file.close();
    }

    // Retrieves a block by its page ID
    // If the block is not in memory, it loads it from disk
    // and caches it for future access
    pub fn getBlock(self: *Pager, page_id: u64) !*Block {
        if (self.blocks.contains(page_id)) {
            print("Block {d} found in cache\n", .{page_id});
            return self.blocks.getPtr(page_id).?; // TODO: handle error
        } else {
            // 1. Initiera med nollor istället för undefined
            var buffer = [_]u8{0} ** constants.BLOCK_SIZE;
            const offset = page_id * constants.BLOCK_SIZE;

            // 2. Läs från filen
            const bytes_read = try self.data_file.preadAll(&buffer, offset);
            print("Bytes read: {d}\n", .{bytes_read});

            try self.blocks.put(page_id, Block{
                .id = page_id,
                .isDirty = false,
                .data = buffer,
            });

            const block = self.blocks.getPtr(page_id).?;

            // 3. Om vi läste 0 bytes, eller om byten för FreeEnd fortfarande är 0
            // (vilket den är nu eftersom vi nollställde bufferten)
            if (bytes_read == 0 or block.getFreeEnd() == 0) {
                print("Block {d} is new, initializing...\n", .{page_id});
                block.initEmpty();
            }

            return block;
        }
    }

    // Marks a block as dirty
    // The actual write to disk will happen during flush
    // or when the pager is deinitialized
    pub fn flushBlock(self: *Pager, page_id: u64) !void {
        var block: Block = undefined;
        const block_ptr = self.blocks.getPtr(page_id);
        if (block_ptr) |ptr| {
            block = ptr.*;
            if (!block.isDirty) {
                return;
            }
        } else {
            return error.BlockNotFound;
        }

        const offset = page_id * constants.BLOCK_SIZE;
        const bytes_written = try self.data_file.pwriteAll(&block.data, offset); // TODO: handle error
        print("Bytes written: {any}\n", .{bytes_written});
        block.isDirty = false;
    }
};
