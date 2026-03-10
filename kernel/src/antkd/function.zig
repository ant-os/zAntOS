const std = @import("std"); 

pub const MAX_MAJOR_FUNCTIONS = 16;

pub const MajorFunction = union(enum(u8)) {
    pub const Tag = std.meta.Tag(MajorFunction);
    pub const Payload = anyopaque;

    unused: void = 0,
    enumerate: extern struct {} = 1,
    example: extern struct { a: usize } = 0xA,
};