const std = @import("std");
const constants = @import("constants.zig");

pub const TypeTag = enum(u8) {
    number = 1,
    text = 2,
    boolean = 3,
};

pub const ValueType = union(TypeTag) {
    number: i32,
    text: []const u8,
    boolean: bool,
};

pub const Field = struct {
    name: []const u8,
    value: ValueType,
};
