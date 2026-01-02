const std = @import("std");
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const LruList = std.DoublyLinkedList;

const constants = @import("constants.zig");
const ValueType = @import("types.zig").ValueType;
const Block = @import("block.zig").Block;
const DiskManager = @import("disk.zig").DiskManager;

/// A node in the LRU cache list to keep track of page access order.
const LruNode = struct {
    page_id: u64,
    node: LruList.Node,
};

/// Manages an in-memory cache of database blocks using an LRU eviction policy.
pub const Pager = struct {
    disk_manager: DiskManager,
    blocks: HashMap(u64, Block),
    lru_list: LruList,
    lru_map: std.AutoHashMap(u64, *LruNode),
    allocator: std.mem.Allocator,

    /// Initializes the pager with a disk manager and empty cache structures.
    pub fn init(_alloc: Allocator, storage_path: []const u8) !Pager {
        return Pager{
            .disk_manager = try DiskManager.init(storage_path),
            .blocks = HashMap(u64, Block).init(_alloc),
            .lru_list = LruList{},
            .lru_map = std.AutoHashMap(u64, *LruNode).init(_alloc),
            .allocator = _alloc,
        };
    }

    /// Releases all resources, including the cache map and the disk manager.
    pub fn deinit(self: *Pager) void {
        self.blocks.deinit();
        self.disk_manager.deinit();
        self.lru_map.deinit();
    }

    /// Updates the LRU list to mark a page as the most recently accessed.
    fn markRecentlyUsed(self: *Pager, page_id: u64) !void {
        if (self.lru_map.get(page_id)) |item| {
            self.lru_list.remove(&item.node);
            self.lru_list.prepend(&item.node);
        } else {
            const item = try self.allocator.create(LruNode);
            item.page_id = page_id;
            self.lru_list.prepend(&item.node);
            try self.lru_map.put(page_id, item);
        }
    }

    /// Evicts the least recently used block if the cache exceeds MAX_PAGES.
    fn evictIfFull(self: *Pager) !void {
        if (self.blocks.count() <= constants.MAX_PAGES) return;

        const last_node_ptr = self.lru_list.last orelse return;
        const item: *LruNode = @fieldParentPtr("node", last_node_ptr);
        const page_id_to_evict = item.page_id;

        try self.flushBlock(page_id_to_evict);

        _ = self.blocks.remove(page_id_to_evict);
        _ = self.lru_map.remove(page_id_to_evict);
        self.lru_list.remove(last_node_ptr);

        self.allocator.destroy(item);

        std.debug.print("LRU: Evicted block {d} to free memory\n", .{page_id_to_evict});
    }

    /// Retrieves a block from cache or loads it from disk if not present.
    pub fn getBlock(self: *Pager, page_id: u64) !*Block {
        if (self.blocks.getPtr(page_id)) |cached_block| {
            try self.markRecentlyUsed(page_id);
            return cached_block;
        }

        try self.evictIfFull();

        var buffer = [_]u8{0} ** constants.BLOCK_SIZE;
        const bytes_read = try self.disk_manager.readPage(page_id, &buffer);

        try self.blocks.put(page_id, Block{
            .id = page_id,
            .isDirty = false,
            .data = buffer,
        });

        const block = self.blocks.getPtr(page_id).?;

        if (bytes_read == 0 or block.getFreeEnd() == 0) {
            block.initEmpty();
        }
        try self.markRecentlyUsed(page_id);

        return block;
    }

    /// Writes a specific block to disk if it has been modified.
    pub fn flushBlock(self: *Pager, page_id: u64) !void {
        const block = self.blocks.getPtr(page_id) orelse return error.BlockNotFound;

        if (!block.isDirty) return;

        try self.disk_manager.writePage(page_id, &block.data);
        block.isDirty = false;
        print("Block {d} flushed to disk\n", .{page_id});
    }

    /// Persists all dirty blocks currently held in the cache to disk.
    pub fn flushAll(self: *Pager) !void {
        var iter = self.blocks.keyIterator();
        while (iter.next()) |page_id| {
            try self.flushBlock(page_id.*);
        }
    }
};
