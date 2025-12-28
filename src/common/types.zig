const std = @import("std");
const constants = @import("constants.zig");

pub const TypeTag = enum(u8) {
    int = 1,
    varchar = 2,
    boolean = 3,
};

pub const ValueType = union(TypeTag) {
    int: i32,
    varchar: []const u8,
    boolean: bool,
};
