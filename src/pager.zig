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
        var it = self.lru_list.first;
        while (it) |node_ptr| {
            const item: *LruNode = @fieldParentPtr("node", node_ptr);
            const next = node_ptr.next;
            self.allocator.destroy(item);
            it = next;
        }
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

test "Pager init and deinit" {
    const allocator = std.testing.allocator;

    const pager = try Pager.init(allocator, "test_data.ivodb");
    defer pager.deinit();

    try pager.flushAll();
    _ = try std.fs.cwd().deleteFile("test_data.ivodb");
}

test "Pager getBlock and flushBlock" {
    const allocator = std.testing.allocator;

    var pager = try Pager.init(allocator, "test_data.ivodb");
    defer pager.deinit();

    const page_id: u64 = 1;
    const block = try pager.getBlock(page_id);
    block.data[0] = 42;
    block.isDirty = true;

    try pager.flushBlock(page_id);

    const block2 = try pager.getBlock(page_id);
    try std.testing.expect(block2.data[0] == 42);

    try pager.flushAll();
    _ = try std.fs.cwd().deleteFile("test_data.ivodb");
}

test "Pager LRU eviction" {
    const allocator = std.testing.allocator;
    const test_file = "test_lru.ivodb";

    // Ensure we start fresh
    std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer {
        pager.deinit();
        std.fs.cwd().deleteFile(test_file) catch {};
    }

    // 1. Fill the pager to its max capacity (0 to MAX_PAGES - 1)
    var i: u64 = 0;
    while (i < constants.MAX_PAGES) : (i += 1) {
        const block = try pager.getBlock(i);
        block.data[0] = @as(u8, @intCast(i));
        block.isDirty = true;
    }

    // 2. Access block 0 and 1 to make them "Recently Used"
    _ = try pager.getBlock(0);
    _ = try pager.getBlock(1);

    // 3. Add one more block to trigger eviction of the LRU block (which is index 2)
    const new_block = try pager.getBlock(constants.MAX_PAGES);
    new_block.data[0] = 99;
    new_block.isDirty = true;

    // 4. Verify eviction
    // Since page 2 was evicted and it was dirty, the Pager should have
    // flushed it to disk during eviction.
    const fetched_evicted = try pager.getBlock(2);

    // This should now be 2, because getBlock(2) re-read it from disk
    // where it was saved during the eviction!
    try std.testing.expectEqual(@as(u8, 2), fetched_evicted.data[0]);

    // Verify that page 2 is now back in cache and something else was kicked out
    try std.testing.expect(pager.blocks.contains(2));
}

test "Pager persistence across restarts" {
    const allocator = std.testing.allocator;
    const test_file = "test_persistence.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const page_id: u64 = 5;

    // Session 1: Write data and shut down
    {
        var pager = try Pager.init(allocator, test_file);
        defer pager.deinit();

        const block = try pager.getBlock(page_id);
        block.data[0] = 77;
        block.isDirty = true;
        try pager.flushBlock(page_id);
    }

    // Session 2: Open again and verify that 77 is still there
    {
        var pager = try Pager.init(allocator, test_file);
        defer pager.deinit();

        const block = try pager.getBlock(page_id);
        try std.testing.expectEqual(@as(u8, 77), block.data[0]);
    }
}

test "Pager initializes new pages correctly" {
    const allocator = std.testing.allocator;
    const test_file = "test_init.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var pager = try Pager.init(allocator, test_file);
    defer pager.deinit();

    // Fetch a page far out in the file that does not exist yet
    const block = try pager.getBlock(100);

    // Verify that initEmpty was called (we check the Magic Number)
    // Assumes OFFSET_MAGIC is 7 and MAGIC_NUMBER is 0x42 based on your Block code
    try std.testing.expect(block.isValid());
    try std.testing.expectEqual(@as(u16, 0), block.getCellCount());
}
