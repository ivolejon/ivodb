const std = @import("std");
const parser = @import("parser.zig");
const Database = @import("database.zig").Database;

pub const Executor = struct {
    db: *Database,
    /// Keeps track of which table the user is currently "in".
    active_table: ?[]const u8,

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
                // Verify that the table actually exists
                _ = try self.db.getTable(data.table);
                self.active_table = data.table;
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

                const stored_key = try block.getValue(i + 2);
                if (stored_key == .text and std.mem.eql(u8, stored_key.text, key)) {
                    const val = try block.getValue(i + 4);
                    return val.text;
                }
                i += 5;
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

                const stored_key = try block.getValue(i + 2);
                if (stored_key == .text and std.mem.eql(u8, stored_key.text, key)) {
                    var del_count: u8 = 0;
                    while (del_count < 5) : (del_count += 1) {
                        try block.deleteValue(i);
                    }
                    block.isDirty = true;
                    return;
                }
                i += 5;
            }
        }
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
