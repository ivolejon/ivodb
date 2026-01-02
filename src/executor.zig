const std = @import("std");
const parser = @import("parser.zig");
const Database = @import("database.zig").Database;

pub const Executor = struct {
    db: *Database,

    pub fn init(db: *Database) Executor {
        return Executor{ .db = db };
    }

    pub fn execute(self: *Executor, cmd: parser.Command) !void {
        switch (cmd) {
            .set => |data| try self.handleSet(data.table, data.key, data.value),
            .get => |data| {
                if (try self.handleGet(data.table, data.key)) |val| {
                    std.debug.print("\"{s}\"\n", .{val});
                } else {
                    std.debug.print("(nil)\n", .{});
                }
            },
            .delete => |data| try self.handleDelete(data.table, data.key),
        }
    }

    fn handleSet(self: *Executor, table_name: []const u8, key: []const u8, value: []const u8) !void {
        // We delete first to handle updates
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
                const header = try block.getValue(i); // Document header (number of fields)
                if (header != .number) {
                    i += 1;
                    continue;
                }

                // In our KV setup, each doc has 2 fields: Key and Value
                // Index i+1: "k" (field name), i+2: key_value, i+3: "v", i+4: value_value
                const stored_key = try block.getValue(i + 2);
                if (stored_key == .text and std.mem.eql(u8, stored_key.text, key)) {
                    const val = try block.getValue(i + 4);
                    return val.text;
                }
                i += 5; // Jump to next document header
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
                    // Delete all 5 cells for this document (header, k-name, k-val, v-name, v-val)
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

test "Executor: Multi-table operations" {
    const allocator = std.testing.allocator;
    // This test assumes Database.init and createTable work as intended.
    // Setup would look like this:
    var db = try Database.init(allocator, "test.db");
    defer db.deinit(allocator);
    _ = try db.createTable("users");
    _ = try db.createTable("meta");
    var exec = Executor.init(db);
    try exec.handleSet("users", "admin", "secret");
    try exec.handleSet("meta", "version", "1.0");
    const val = try exec.handleGet("users", "admin");
    try std.testing.expectEqualStrings("secret", val.?);
}
