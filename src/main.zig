const std = @import("std");
const ivodb = @import("ivodb");
const storage = @import("storage/pager.zig");
const print = std.debug.print;
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var pager = try storage.Pager.init(allocator, "data.ivodb");
    defer pager.deinit();

    const page_id: u64 = 0;

    var block = try pager.getBlock(page_id);
    // print("Block ID: {d}\n", .{block.id});
    // print("Cell Count: {d}\n", .{block.getCellCount()});

    // const count = block.getCellCount();
    // var i: u16 = 0;
    // while (i < count) : (i += 1) {
    //     const text = try block.getVarchar(i);
    //     std.debug.print("Index {d}: {s}\n", .{ i, text });
    // }

    // const block = try pager.getBlock(page_id);
    // const text = "Hello, Ivodb!";
    // try block.insertVarchar(text);
    // try pager.flushBlock(page_id);
    //
    // try block.insertValue(.{ .int32 = 1337 });
    // try block.insertValue(.{ .varchar = "Zig is powerful" });

    const val1 = try block.getValue(2);
    switch (val1) {
        .int32 => |i| std.debug.print("Fick int: {d}\n", .{i}),
        .varchar => |s| std.debug.print("Fick str: {s}\n", .{s}),
        .boolean => |b| std.debug.print("Fick bool: {any}\n", .{b}),
    }

    // try pager.flushBlock(0);
}
