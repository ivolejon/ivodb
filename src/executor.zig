const std = @import("std");
const parser = @import("parser.zig");
const Database = @import("database.zig").Database;

pub const Executor = struct {
    db: *Database,
    active_table_buf: [256]u8 = undefined,
    active_table_len: usize = 0,
    active_table: ?[]const u8 = null,

    pub fn init(db: *Database) Executor {
        return Executor{
            .db = db,
            .active_table = null,
        };
    }

    /// Routes commands from the parser to the appropriate logic.
    pub fn execute(self: *Executor, cmd: parser.Command) !void {
        switch (cmd) {
            .create => |data| {
                _ = try self.db.createTable(data.table);
                std.debug.print("OK: Table '{s}' created.\n", .{data.table});
            },
            .use => |data| {
                // Verify that the table actually existsGE
                _ = try self.db.getTable(data.table);

                const len = @min(data.table.len, self.active_table_buf.len);
                std.mem.copyForwards(u8, &self.active_table_buf, data.table[0..len]);
                self.active_table_len = len;

                self.active_table = self.active_table_buf[0..len];
                std.debug.print("Switched to table '{s}'.\n", .{data.table});
            },
            .set => |data| {
                const table_name = self.active_table orelse return error.NoTableSelected;
                try self.handleSet(table_name, data.key, data.value);
                std.debug.print("OK\n", .{});
            },
            .get => |data| {
                const table_name = self.active_table orelse return error.NoTableSelected;
                if (try self.handleGet(table_name, data.key)) |val| {
                    std.debug.print("\"{s}\"\n", .{val});
                } else {
                    std.debug.print("(nil)\n", .{});
                }
            },
            .delete => |data| {
                const table_name = self.active_table orelse return error.NoTableSelected;
                try self.handleDelete(table_name, data.key);
                std.debug.print("OK\n", .{});
            },
            .scan => |_| {
                std.debug.print("Scan not implemented yet.\n", .{});
            },
        }
    }

    fn handleSet(self: *Executor, table_name: []const u8, key: []const u8, value: []const u8) !void {
        try self.handleDelete(table_name, key);
        var table = try self.db.getTable(table_name);
        try table.insertKeyValuePair(key, value);
    }

    fn handleGet(self: *Executor, table_name: []const u8, key: []const u8) !?[]const u8 {
        var table = try self.db.getTable(table_name);
        var p: u64 = 0;

        while (p < table.total_pages) : (p += 1) {
            const block = try table.getBlock(p);
            var i: u16 = 0;
            const cell_count = block.getCellCount();

            while (i < cell_count) {
                const header = try block.getValue(i);

                if (header != .number) {
                    i += 1;
                    continue;
                }

                // Header + 6 dataceller krävs för ett fullständigt dokument
                if (i + 6 >= cell_count) break;

                const stored_key = try block.getValue(i + 4);

                if (stored_key == .text and std.mem.eql(u8, stored_key.text, key)) {
                    const id_cell = try block.getValue(i + 2);
                    if (id_cell == .text) {
                        printId(id_cell.text);
                    }

                    const val = try block.getValue(i + 6);
                    if (val == .text) {
                        return val.text;
                    }
                }

                const num_fields = @as(u16, @intCast(header.number));
                i += 1 + (num_fields * 2);
            }
        }
        return null;
    }

    fn handleDelete(self: *Executor, table_name: []const u8, key: []const u8) !void {
        var table = try self.db.getTable(table_name);
        var p: u64 = 0;

        while (p < table.total_pages) : (p += 1) {
            const block = try table.getBlock(p);
            var i: u16 = 0;

            while (i < block.getCellCount()) {
                const header = try block.getValue(i);
                if (header != .number) {
                    i += 1;
                    continue;
                }

                // Antal fält (bör vara 3: _id, k, v)
                const num_fields = @as(u16, @intCast(header.number));

                const cells_in_doc = 1 + (num_fields * 2);

                // (i+1=_id, i+2=id_val, i+3=k, i+4=key_val)
                if (i + 4 >= block.getCellCount()) break;

                const stored_key = try block.getValue(i + 4);
                if (stored_key == .text and std.mem.eql(u8, stored_key.text, key)) {
                    var del_idx: u8 = 0;
                    while (del_idx < cells_in_doc) : (del_idx += 1) {
                        try block.deleteValue(i);
                    }

                    block.isDirty = true;
                    return;
                }

                i += cells_in_doc;
            }
        }
    }

    fn printId(id_bytes: []const u8) void {
        var buf: [32]u8 = undefined;
        for (id_bytes, 0..) |byte, idx| {
            _ = std.fmt.bufPrint(buf[idx * 2 .. (idx * 2) + 2], "{x:0>2}", .{byte}) catch unreachable;
        }

        std.debug.print("[ID: {s}] ", .{buf});
    }
};

// --- Tests ---

test "Executor: CREATE, USE and KV flow" {
    const allocator = std.testing.allocator;
    const db_file = "test_exec.ivodb";
    std.fs.cwd().deleteFile(db_file) catch {};
    defer std.fs.cwd().deleteFile(db_file) catch {};

    var db = try Database.init(allocator, db_file);
    defer db.deinit(allocator);

    var exec = Executor.init(db);

    // 1. Create and Use
    try exec.execute(.{ .create = .{ .table = "users" } });
    try exec.execute(.{ .use = .{ .table = "users" } });

    // 2. Set and Get
    try exec.execute(.{ .set = .{ .key = "ivo", .value = "db" } });

    // Manual check to verify internal logic
    const val = try exec.handleGet("users", "ivo");
    try std.testing.expectEqualStrings("db", val.?);
}
