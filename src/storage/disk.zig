const std = @import("std");
const common = @import("../common/mod.zig");
const constants = common.constants;

pub const DiskManager = struct {
    file: std.fs.File,

    pub fn init(storage_path: []const u8) !DiskManager {
        // const file = try std.fs.cwd().openFile(storage_path, .{ .mode = .read_write });
        const file = try std.fs.cwd().createFile(storage_path, .{
            .read = true, // Måste vara true för preadAll
            .truncate = false, // Måste vara false för att inte tömma db:n varje gång
            .exclusive = false, // Gör att vi kan öppna en befintlig fil
        });
        return DiskManager{ .file = file };
    }

    pub fn readPage(self: *DiskManager, page_id: u64, buffer: *[constants.BLOCK_SIZE]u8) !usize {
        const file_size = (try self.file.stat()).size;
        const offset = page_id * constants.BLOCK_SIZE;

        // Om vi försöker läsa utanför filen, returnera bara nollor
        if (offset >= file_size) {
            @memset(buffer, 0);
            return 0;
        }

        return try self.file.preadAll(buffer, offset);
    }

    pub fn writePage(self: *DiskManager, page_id: u64, data: []const u8) !void {
        const offset = page_id * constants.BLOCK_SIZE;
        try self.file.pwriteAll(data, offset);
        // I framtiden kan vi lägga till self.file.sync() här för extra säkerhet
    }

    pub fn getPageCount(self: *DiskManager) !u64 {
        // 1. Hämta filens storlek i bytes
        const file_info = try self.file.stat();
        const file_size = file_info.size;

        // 2. Dela storleken med din BlockSize (t.ex. 4096)
        // Vi använder din konstant för BlockSize här
        const page_size = constants.BLOCK_SIZE;

        return file_size / page_size;
    }

    pub fn deinit(self: *DiskManager) void {
        self.file.close();
    }
};
