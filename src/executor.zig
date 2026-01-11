const std = @import("std");
const parser = @import("parser.zig");
const Database = @import("database.zig").Database;
const TableIterator = @import("table_iter.zig").TableIterator;

pub const Executor = struct {
    db: *Database,
    active_table_buf: [256]u8 = undefined,
    active_table_len: usize = 0,
    active_table: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, db: *Database) Executor {
        return Executor{
            .db = db,
            .active_table = null,
            .allocator = alloc,
        };
    }

    pub fn execute(self: *Executor, cmd: parser.Command) !void {
        switch (cmd) {
            .create => |data| {
                _ = try self.db.createTable(data.table);
                std.debug.print("OK: Table '{s}' created.\n", .{data.table});
            },
            .use => |data| {
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
                    // Vi printar värdet och frigör det eftersom handleGet gjorde en dupe
                    std.debug.print("\"{s}\"\n", .{val});
                    self.allocator.free(val);
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
                const table_name = self.active_table orelse return error.NoTableSelected;
                try self.handleScan(table_name);
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
        var iter = TableIterator{ .table = &table };

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        while (try iter.nextDocument(arena_alloc)) |fields| {
            // Rensa minnet för varje dokument som inte matchar
            defer _ = arena.reset(.free_all);

            var found_key = false;
            var result_val: ?[]const u8 = null;
            var id_val: ?[]const u8 = null;

            for (fields) |field| {
                if (std.mem.eql(u8, field.name, "k") and field.value == .text) {
                    if (std.mem.eql(u8, field.value.text, key)) found_key = true;
                }
                if (std.mem.eql(u8, field.name, "v") and field.value == .text) {
                    result_val = field.value.text;
                }
                if (std.mem.eql(u8, field.name, "_id") and field.value == .text) {
                    id_val = field.value.text;
                }
            }

            if (found_key) {
                if (id_val) |id| self.printId(id);

                return if (result_val) |v| try self.allocator.dupe(u8, v) else null;
            }
        }
        return null;
    }

    fn handleScan(self: *Executor, table_name: []const u8) !void {
        var table = try self.db.getTable(table_name);
        var iter = TableIterator{ .table = &table };

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        while (try iter.nextDocument(arena_alloc)) |fields| {
            defer _ = arena.reset(.free_all);

            // Printa ID först
            for (fields) |field| {
                if (std.mem.eql(u8, field.name, "_id") and field.value == .text) {
                    self.printId(field.value.text);
                }
            }

            for (fields) |field| {
                if (std.mem.eql(u8, field.name, "_id")) continue;

                switch (field.value) {
                    .text => |t| std.debug.print("\"{s}\" ", .{t}),
                    .number => |n| std.debug.print("{d} ", .{n}),
                    .boolean => |b| std.debug.print("{s} ", .{if (b) "true" else "false"}),
                }
            }
            std.debug.print("\n", .{});
        }
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

                const num_fields = @as(u16, @intCast(header.number));
                const cells_in_doc = 1 + (num_fields * 2);

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

    fn printId(self: *Executor, id_bytes: []const u8) void {
        _ = self;
        var buf: [32]u8 = undefined;
        for (id_bytes, 0..) |byte, idx| {
            _ = std.fmt.bufPrint(buf[idx * 2 .. (idx * 2) + 2], "{x:0>2}", .{byte}) catch unreachable;
        }
        std.debug.print("[ID: {s}] ", .{buf});
    }
};

// --- Tester ---

test "Executor: the flow" {
    const allocator = std.testing.allocator;
    const db_file = "test_exec.ivodb";
    std.fs.cwd().deleteFile(db_file) catch {};
    defer std.fs.cwd().deleteFile(db_file) catch {};

    var db = try Database.init(allocator, db_file);
    defer db.deinit(allocator);

    var exec = Executor.init(allocator, db);

    try exec.execute(.{ .create = .{ .table = "users" } });
    try exec.execute(.{ .use = .{ .table = "users" } });

    // Test SET
    try exec.execute(.{ .set = .{ .key = "ivo", .value = "db" } });
    try exec.execute(.{ .set = .{ .key = "zig", .value = "lang" } });

    // Test GET
    const val = try exec.handleGet("users", "ivo");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("db", val.?);
    allocator.free(val.?);

    // Test SCAN
    try exec.execute(.{ .scan = .{} });

    // Test DELETE
    try exec.execute(.{ .delete = .{ .key = "ivo" } });
    const val_after = try exec.handleGet("users", "ivo");
    try std.testing.expect(val_after == null);
}
