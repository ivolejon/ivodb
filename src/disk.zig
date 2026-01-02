const std = @import("std");
const constants = @import("constants.zig");

/// Handles low-level file I/O operations, mapping page IDs to physical file offsets.
pub const DiskManager = struct {
    file: std.fs.File,

    /// Opens or creates a database file with read and write permissions.
    pub fn init(storage_path: []const u8) !DiskManager {
        const file = try std.fs.cwd().createFile(storage_path, .{
            .read = true,
            .truncate = false,
            .exclusive = false,
        });
        return DiskManager{ .file = file };
    }

    /// Reads a specific page into the provided buffer using a thread-safe offset read.
    /// Returns 0 if the requested page is beyond the current file size.
    pub fn readPage(self: *DiskManager, page_id: u64, buffer: *[constants.BLOCK_SIZE]u8) !usize {
        const file_size = (try self.file.stat()).size;
        const offset = page_id * constants.BLOCK_SIZE;

        if (offset >= file_size) {
            @memset(buffer, 0);
            return 0;
        }

        return try self.file.preadAll(buffer, offset);
    }

    /// Writes data to a specific page on disk using a thread-safe offset write.
    pub fn writePage(self: *DiskManager, page_id: u64, data: []const u8) !void {
        const offset = page_id * constants.BLOCK_SIZE;
        try self.file.pwriteAll(data, offset);
    }

    /// Calculates the total number of pages currently stored in the database file.
    pub fn getPageCount(self: *DiskManager) !u64 {
        const file_info = try self.file.stat();
        const file_size = file_info.size;
        const page_size = constants.BLOCK_SIZE;

        return file_size / page_size;
    }

    /// Closes the database file handle.
    pub fn deinit(self: *DiskManager) void {
        self.file.close();
    }
};
