const std = @import("std");
const Allocator = std.mem.Allocator;

var in_buffer: [4096]u8 = undefined; // outside
var out_buffer: [4096]u8 = undefined; // outside
var stdin: std.fs.File.Reader = undefined; // outside
var stdout: std.fs.File.Writer = undefined; // outside

pub const IoContext = struct {
    in: *std.Io.Reader,
    out: *std.Io.Writer,

    pub fn init() IoContext {
        stdin = std.fs.File.stdin().reader(&in_buffer);
        stdout = std.fs.File.stdout().writer(&out_buffer);

        return .{
            .in = &stdin.interface,
            .out = &stdout.interface,
        };
    }

    pub fn print(self: *const IoContext, comptime str: []const u8, args: anytype) !void {
        try self.out.print(str, args);
        try self.out.flush();
    }

    pub fn read_line(self: *const IoContext) !?[]const u8 {
        const line = try self.in.takeDelimiterInclusive('\n');
        return std.mem.trimEnd(u8, line, "\r\n");
    }

    pub fn flush_input(self: *const IoContext) void {
        _ = self;
        @memset(&in_buffer, 0);
    }
};
