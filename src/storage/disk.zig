const std = @import("std");
const common = @import("../common/mod.zig");
const constants = common.constants;

pub const DiskManager = struct {
    file: std.fs.File,

    pub fn init(storage_path: []const u8) !DiskManager {
        const file = try std.fs.cwd().openFile(storage_path, .{ .mode = .read_write });
        return DiskManager{ .file = file };
    }

    pub fn readPage(self: *DiskManager, page_id: u64, buffer: *[constants.BLOCK_SIZE]u8) !usize {
        const offset = page_id * constants.BLOCK_SIZE;
        return try self.file.preadAll(buffer, offset);
    }

    pub fn writePage(self: *DiskManager, page_id: u64, data: []const u8) !void {
        const offset = page_id * constants.BLOCK_SIZE;
        try self.file.pwriteAll(data, offset);
        // I framtiden kan vi lägga till self.file.sync() här för extra säkerhet
    }

    pub fn deinit(self: *DiskManager) void {
        self.file.close();
    }
};
