const std = @import("std");
const ivodb = @import("ivodb");
const storage = @import("storage/pager.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var pager = try storage.Pager.init(allocator, "data.ivodb");
    defer pager.deinit();
    
    

    const page_id: u64 = 0;

    const block = try pager.getBlock(page_id);
    const text = "Hello, Ivodb!";
    try block.insertVarchar(text);
    try pager.flushBlock(page_id);
}
