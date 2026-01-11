const std = @import("std");
const parser = @import("parser.zig");
const Database = @import("database.zig").Database;
const TableIterator = @import("table_iter.zig").TableIterator;

pub const Executor = struct {
    db: *Database,
    active_table_buf: [256]u8 = undefined,
    active_table_len: usize = 0,
    active_table: ?[]const u8 = null,
    allocator: std.mem.Allocator = undefined,

    pub fn init(alloc: std.mem.Allocator, db: *Database) Executor {
        return Executor{
            .db = db,
            .active_table = null,
            .allocator = alloc,
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

    fn handleGet(self: *Executor, table_name: []const u8, key: []const u8) !?[]const u8 {
        var table = try self.db.getTable(table_name);
        var iter = TableIterator{ .table = &table };

        // Vi använder en Arena för temporär data under sökningen
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        while (try iter.nextDocument(arena.allocator())) |fields| {
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
                if (id_val) |id| printId(id);
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

        std.debug.print("\n--- Scanning table: {s} ---\n", .{table_name});

        while (try iter.nextDocument(arena.allocator())) |fields| {
            defer _ = arena.reset(.free_all);

            // Vi börjar varje rad med att kolla efter _id för att få samma stil som GET
            for (fields) |field| {
                if (std.mem.eql(u8, field.name, "_id") and field.value == .text) {
                    printId(field.value.text);
                }
            }

            // Sen skriver vi ut resten av fälten
            for (fields) |field| {
                // Hoppa över _id här eftersom vi redan skrivit ut det snyggt
                if (std.mem.eql(u8, field.name, "_id")) continue;

                switch (field.value) {
                    .text => |t| std.debug.print("\"{s}\" ", .{t}),
                    .number => |n| std.debug.print("{d} ", .{n}),
                    .boolean => |b| std.debug.print("{s} ", .{if (b) "true" else "false"}),
                }
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("--- End of scan ---\n", .{});
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

    var exec = Executor.init(allocator, db);

    // 1. Create and Use
    try exec.execute(.{ .create = .{ .table = "users" } });
    try exec.execute(.{ .use = .{ .table = "users" } });

    // 2. Set and Get
    try exec.execute(.{ .set = .{ .key = "ivo", .value = "db" } });

    // Manual check to verify internal logic
    const val = try exec.handleGet("users", "ivo");
    try std.testing.expectEqualStrings("db", val.?);
}
