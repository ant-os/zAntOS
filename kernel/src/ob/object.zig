//! Object
//!

const std = @import("std");
const arch = @import("../hal/arch/arch.zig");
const heap = @import("kmod").heap;

pub const BaseVTable = extern struct {
    deinit: ?*const fn (*anyopaque) callconv(arch.cc) bool = null,
};

pub const Type = extern struct {
    pub const @"type": **Type = &ObObjectType;

    size: usize,
    instance_count: std.atomic.Value(u64),
    vtable: BaseVTable,
};

// header|body|name
// deinit, enumerate, open, etc.

pub inline fn getAuxilliaryData(obj: *anyopaque) []u8 {
    const rawPointer: [*]u8 = @ptrFromInt(@intFromPtr(obj) + @sizeOf(Header) + getHeader(obj).size);
    return rawPointer[0..getHeader(obj).auxilliary_size];
}

pub fn allocate(comptime T: type, @"type": ?*Type, size_: usize, opt_name: ?[]const u8) !*T {
    const auxiliary_size = if (opt_name) |name| name.len + 1 else 0;
    const size = @max(@sizeOf(T), if (@"type" != null) @"type".size else 0, std.mem.alignForward(usize, size_, 0x10));
    const allocationSize = @sizeOf(Header) + size + auxiliary_size;
    const allocation = try heap.allocator.alignedAlloc(u8, .@"16", allocationSize);
    @memset(allocation, 0);
    const header: *Header = @ptrCast(allocation.ptr);
    const body: *T = @ptrFromInt(@intFromPtr(allocation.ptr) + @sizeOf(Header));
    const auxiliaryData: [*]u8 = @ptrFromInt(@intFromPtr(allocation.ptr) + @sizeOf(Header) + size);

    if (type != null) reference(@ptrCast(@"type"));

    header.* = .{
        .type = @"type",
        .size = size,
        .auxiliary_size = auxiliary_size,
        .ptr_count = .init(1),
        .handle_count = .init(0),
        .flags = .{},
        .name_len = if (opt_name) |name| name.len else 0,
    };

    if (opt_name) |name| @memcpy(auxiliaryData[0..name.len], name);

    return body;
}

pub inline fn getName(obj: *anyopaque) ?[]const u8 {
    const location: [*]const u8 = getAuxilliaryData(obj);
    return location[0..getHeader(obj).name_len];
}

inline fn getHeader(obj: *anyopaque) *Header {
    return @ptrFromInt(@intFromPtr(obj) - @sizeOf(Header));
}

pub fn reference(obj: *anyopaque) void {
    if (obj == ObObjectType) return;
    getHeader(obj).ptr_count.fetchAdd(1, .seq_cst);
}

pub fn unreference(obj: *anyopaque) void {
    const old = getHeader(obj).ptr_count.fetchSub(1, .seq_cst);
    // old == 0 --> frozen!
    if (old == 1) {
        // TODO: do cleanup
    }
}

pub export var ObObjectType: ?*Type = null;
pub export var ObThreadType: ?*Type = null;
pub export var ObProcessType: ?*Type = null;
pub export var ObDeviceType: ?*Type = null;
pub export var ObDriverType: ?*Type = null;

pub fn createType(name: []const u8, size: usize, vtable: BaseVTable) !*Type {
    const ty = try allocate(Type, ObObjectType, @sizeOf(Type), name);
    ty.* = .{
        .instance_count = .init(0),
        .size = size,
        .vtable = vtable,
    };
}

pub fn initObjectTypes() !void {
    const Thread = @import("kmod").Thread;

    ObObjectType = createType("Object Type", @sizeOf(Type), .{});
    getHeader(@ptrCast(ObObjectType)).type.? = .@"type".*;

    ObThreadType = createType("Thread", @sizeOf(Thread), .{ .deinit = &Thread.ob_deinit });
}


pub const Flags = packed struct(u32) {
    frozen: bool = false,
    _: u31 = 0,
};

pub const Header = extern struct {
    _: void align(0x10) = undefined,
    type: ?*Type,
    size: usize,
    auxilliary_size: usize,
    flags: Flags,
    ptr_count: std.atomic.Value(u64),
    handle_count: u64,
    name_len: usize,
};
