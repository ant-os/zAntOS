const std = @import("std");
const capi = @import("../antk/antk.zig").c;

pub const MAX_MAJOR_FUNCTIONS = 16;

pub const MajorFunction = union(enum(u8)) {
    pub const Tag = std.meta.Tag(MajorFunction);
    pub const Payload = anyopaque;

    unused: void = 0,
    enumerate: extern struct {} = 1,
    read: capi.IRP_PARAMS_READ = capi.IRP_MJ_READ,
    write: capi.IRP_PARAMS_WRITE = capi.IRP_MJ_WRITE,
    example: extern struct { a: usize } = 0xA,
};