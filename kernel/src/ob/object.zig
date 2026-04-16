//! Object 
//! 

const std = @import("std");
const arch = @import("../hal/arch/arch.zig");
const heap = @import("kmod").heap;

const Type = enum(u8) {
    thread,
    process,
    hardware_io,
    driver,
    device,
    _,
};

pub const VTable = struct {
    deinit: *const fn(*anyopaque) callconv(arch.cc) void,
};

pub const ObType = extern struct {
    size: usize,
    instance_count: std.atomic.Value(u64),
    // ...
};

// header|body|name
// deinit, enumerate, open, etc.

pub fn allocate(
    comptime T: ?type,
    @"type": *ObType,
    size: usize,
    name: ?[]const u8,
) !*Instance(T) {
    if ((T == null and size < @sizeOf(T.?)) or size < @"type".size) return error.InvalidParameter;

    referenceByPointer(@ptrCast(@"type"));
    errdefer unref(@ptrCast(@"type"));

    const nameLenght = if (name == null) 0 else name.?.len;
    const allocationSize = @sizeOf(Header) + size + nameLenght;
    const allocation = try heap.allocator.alignedAlloc(u8, .@"16", allocationSize);
    @memset(allocation, 0);
    const header: *Header = @ptrCast(allocation.ptr);
    const instance: *Instance(null) = @ptrFromInt(@intFromPtr(allocation.ptr) + @sizeOf(Header));
    header.* = .{
        .@"type" = @"type",
        .ptr_count = .init(1),
        .handle_count = 0,
        .name_len = nameLenght,
        .size = size,
    };
    
    if (name) @memcpy(getName(instance).?, name.?);

    return instance;
}

pub inline fn getName(obj: *Instance(null)) ?[]const u8 {
    if (obj._header().name_len == 0) return null;
    const location: [*]const u8 = @ptrFromInt(@intFromPtr(obj) +  obj._header().size);
    return location[0..obj._header().name_len];
}

pub fn Instance(comptime T: ?type) type { 
    if (@alignOf(T) > 16) @compileError("alignment limit exceeded");
    if (@sizeOf(T) <= 16) @compileError("object must be at least 16 bytes");
    return struct {
        inner: (T orelse u64) align(0x10),

        inline fn coerce(self: anytype) *@This() {
            return @as(*@This(), @constCast(@volatileCast(self)));
        }

        pub inline fn get(self: anytype) *(T orelse void) {
            comptime if (T == null) @compileError("get() called on untyped instance");
            return @ptrCast(coerce(self));
        }

        pub inline fn _header(self: anytype) *Header{
            return @ptrFromInt(@intFromPtr(coerce(self)) - @sizeOf(Header));
        }

        pub inline fn raw(self: anytype) *align(0x10) void {
            return @ptrCast(coerce(self));
        }
    };
}

pub fn referenceByPointer(obj: *Instance(null)) void {
    if (obj == @as(*Instance(null), @ptrCast(&ObObjectType.instance_count))) return;
    obj._header().ptr_count.fetchAdd(1, .seq_cst);
}

pub fn unref(obj: *Instance(null)) void {
    const old = obj._header().ptr_count.fetchSub(1, .seq_cst);
    // old == 0 --> frozen!
    if (old == 1) {
        // TODO: do cleanup
    }
}

pub export var ObObjectType: *ObType = &(extern struct {
    const NAME: [10] u8 = "Object Type"[0..10].*;

    header: Header = .{
        .@"type" = undefined,
        .size = @sizeOf(ObType),
        .ptr_count = 0,
        .handle_count = 0,
        .name_len = NAME.len,
    },
    body: ObType = .{
        .size = @sizeOf(ObType),
        .instance_count = .init(1),
    },
    name: [NAME.len]u8 = NAME,
}{}).body;


pub const Header = extern struct {
    _: void align(0x10) = undefined,
    @"type": *ObType,
    size: usize,
    ptr_count: std.atomic.Value(u64),
    handle_count: u64 = 0,
    name_len: usize = 0,

    pub fn ref(self: *Header) void {
        self.ptr_count += 1;
    }

    pub fn unref(self: *Header) void {
        if (self.ptr_count <= 1) return self.vtable.deinit(self);
        self.ptr_count -= 1;
    }
};

comptime {
    @compileLog(@sizeOf(Header));
    @compileLog(@alignOf(Header));
}

