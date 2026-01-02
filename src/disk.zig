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

test "DiskManager: basic read and write" {
    const test_file = "test_disk_basic.ivodb";
    // Rensa om den finns
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var dm = try DiskManager.init(test_file);
    defer dm.deinit();

    const page_id: u64 = 2;
    var write_buffer = [_]u8{0} ** constants.BLOCK_SIZE;
    write_buffer[0] = 'H';
    write_buffer[1] = 'i';

    // Skriv till sida 2 (offset 8192 om blockstorlek är 4096)
    try dm.writePage(page_id, &write_buffer);

    var read_buffer = [_]u8{0} ** constants.BLOCK_SIZE;
    const bytes_read = try dm.readPage(page_id, &read_buffer);

    try std.testing.expectEqual(@as(usize, constants.BLOCK_SIZE), bytes_read);
    try std.testing.expectEqual(@as(u8, 'H'), read_buffer[0]);
    try std.testing.expectEqual(@as(u8, 'i'), read_buffer[1]);
}

test "DiskManager: read non-existent page" {
    const test_file = "test_disk_nonexist.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var dm = try DiskManager.init(test_file);
    defer dm.deinit();

    var read_buffer = [_]u8{0} ** constants.BLOCK_SIZE;
    // Läs sida 10 i en tom fil
    const bytes_read = try dm.readPage(10, &read_buffer);

    try std.testing.expectEqual(@as(usize, 0), bytes_read);
    // Bufferten ska vara nollställd enligt koden
    try std.testing.expectEqual(@as(u8, 0), read_buffer[0]);
}

test "DiskManager: page count calculation" {
    const test_file = "test_disk_count.ivodb";
    std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var dm = try DiskManager.init(test_file);
    defer dm.deinit();

    try std.testing.expectEqual(@as(u64, 0), try dm.getPageCount());

    const data = [_]u8{0} ** constants.BLOCK_SIZE;

    // Skriv sida 0
    try dm.writePage(0, &data);
    try std.testing.expectEqual(@as(u64, 1), try dm.getPageCount());

    // Skriv sida 4 (skapar "hål" i filen, men filstorleken blir 5 sidor)
    try dm.writePage(4, &data);
    try std.testing.expectEqual(@as(u64, 5), try dm.getPageCount());
}
