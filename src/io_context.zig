const std = @import("std");

// var io_context: IoContext = undefined; // this one is initialized

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
};
