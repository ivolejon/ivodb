const std = @import("std");
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const LruList = std.DoublyLinkedList;

const constants = @import("constants.zig");
const ValueType = @import("types.zig").ValueType;
const Block = @import("block.zig").Block;
const DiskManager = @import("disk.zig").DiskManager;

const LruNode = struct {
    page_id: u64,
    node: LruList.Node,
};

pub const Pager = struct {
    disk_manager: DiskManager,
    blocks: HashMap(u64, Block),
    lru_list: LruList,
    // För att snabbt hitta noden i listan givet ett page_id
    lru_map: std.AutoHashMap(u64, *LruNode),
    allocator: std.mem.Allocator,

    pub fn init(_alloc: Allocator, storage_path: []const u8) !Pager {
        return Pager{
            .disk_manager = try DiskManager.init(storage_path),
            .blocks = HashMap(u64, Block).init(_alloc),
            .lru_list = LruList{},
            .lru_map = std.AutoHashMap(u64, *LruNode).init(_alloc),
            .allocator = _alloc,
        };
    }

    pub fn deinit(self: *Pager) void {
        self.blocks.deinit();
        self.disk_manager.deinit();
        self.lru_map.deinit();
    }

    fn markRecentlyUsed(self: *Pager, page_id: u64) !void {
        if (self.lru_map.get(page_id)) |item| {
            // Om blocket redan finns i listan, flytta det till toppen
            self.lru_list.remove(&item.node);
            self.lru_list.prepend(&item.node);
        } else {
            // Om det är ett nytt block i cachen, skapa en ny nod
            const item = try self.allocator.create(LruNode);
            item.page_id = page_id;
            self.lru_list.prepend(&item.node);
            try self.lru_map.put(page_id, item);
        }
    }

    fn evictIfFull(self: *Pager) !void {
        if (self.blocks.count() <= constants.MAX_PAGES) return;

        // Hämta det sista elementet (Least Recently Used)
        const last_node_ptr = self.lru_list.last orelse return;
        const item: *LruNode = @fieldParentPtr("node", last_node_ptr);
        const page_id_to_evict = item.page_id;

        // 1. Om blocket är ändrat, spara det till disk!
        try self.flushBlock(page_id_to_evict);

        // 2. Ta bort från alla strukturer
        _ = self.blocks.remove(page_id_to_evict);
        _ = self.lru_map.remove(page_id_to_evict);
        self.lru_list.remove(last_node_ptr);

        // 3. Frigör nodens minne
        self.allocator.destroy(last_node_ptr);

        std.debug.print("LRU: Evicted block {d} to free memory\n", .{page_id_to_evict});
    }

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

        // Initiera om det är en ny sida
        if (bytes_read == 0 or block.getFreeEnd() == 0) {
            block.initEmpty();
        }
        try self.markRecentlyUsed(page_id);

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

test "Pager can load and flush blocks" {
    const allocator = std.heap.page_allocator;
    {
        var file = try std.fs.cwd().createFile("test_data.ivodb", .{ .truncate = true });
        defer file.close();
    }
    var pager = try Pager.init(allocator, "test_data.ivodb");
    defer pager.deinit();

    const page_id: u64 = 0;

    var block = try pager.getBlock(page_id);
    block.initEmpty();
    try block.insertValue(.{ .text = "Test string" });
    try pager.flushBlock(page_id);

    const loaded_block = try pager.getBlock(page_id);
    const value = try loaded_block.getValue(0);
    try std.testing.expectEqual(block, loaded_block);
    try std.testing.expectEqualStrings("Test string", value.text);
}
