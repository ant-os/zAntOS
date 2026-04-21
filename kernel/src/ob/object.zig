//! Object
//!

const std = @import("std");
const arch = @import("../hal/arch/arch.zig");
const heap = @import("kmod").heap;
const log = std.log.scoped(.object_manager);

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
    const size = @max(if (T != anyopaque) @sizeOf(T) else 0, if (@"type" != null) @"type".?.size else 0, std.mem.alignForward(usize, size_, 0x10));
    const allocationSize = @sizeOf(Header) + size + auxiliary_size;
    const allocation = try heap.allocator.alignedAlloc(u8, .@"16", allocationSize);
    @memset(allocation, 0);
    const header: *Header = @ptrCast(allocation.ptr);
    const body: *T = @ptrFromInt(@intFromPtr(allocation.ptr) + @sizeOf(Header));
    const auxiliaryData: [*]u8 = @ptrFromInt(@intFromPtr(allocation.ptr) + @sizeOf(Header) + size);

    if (@"type" != null) referenceRaw(@ptrCast(@"type"));

    header.* = .{
        .type = @"type",
        .size = size,
        .auxilliary_size = auxiliary_size,
        .ptr_count = .init(1),
        .handle_count = .init(0),
        .flags = .{ .typed = .{} },
        .name_len = if (opt_name) |name| name.len else 0,
    };

    if (opt_name) |name| @memcpy(auxiliaryData[0..name.len], name);

    return body;
}

pub inline fn getName(obj: *anyopaque) ?[]const u8 {
    const location: [*]const u8 = getAuxilliaryData(obj);
    return location[0..getHeader(obj).name_len];
}

pub inline fn getHeader(obj: *anyopaque) *Header {
    return @ptrFromInt(@intFromPtr(obj) - @sizeOf(Header));
}

pub fn referenceRaw(obj: *anyopaque) void {
    if (obj == @as(*anyopaque, @ptrCast(ObObjectType.?))) return;
    _ = getHeader(obj).ptr_count.fetchAdd(1, .seq_cst);
}

pub fn referenceObject(obj: *anyopaque, ty: *Type) error{InvalidParameter}!void {
    log.debug("ref(header={any}, ty={any})", .{getHeader(obj), ty});
    if (getHeader(obj).type != ty) return error.InvalidParameter;
    referenceRaw(obj);
}

pub inline fn checkObjectType(obj: *anyopaque, ty: *Type) bool {
    return getHeader(obj).type == ty;
}

pub fn referenceKnownObject(obj: *anyopaque, comptime T: type) error{InvalidParameter}!*T {
    if (!@hasDecl(T, "knownObjectType")) @compileError("invalid known object type");
    const knownType: *KnownTypeInstance = &@field(T, "knownObjectType");

    if (getHeader(obj).type != knownType.getPointer()) return error.InvalidParameter;
    referenceRaw(obj);
    return @ptrCast(@alignCast(obj));
}

pub fn unreferenceObject(comptime T: type, obj: *T) void {
    referenceRaw(@ptrCast(obj));
}

pub fn unreferenceRaw(obj: *anyopaque) void {
    const header = getHeader(obj);
    var oldValue: u64 = 1;
    while (header.ptr_count.cmpxchgWeak(
        oldValue,
        oldValue - 1,
        .seq_cst,
        .monotonic,
    )) |val| : (oldValue = val) {
        // the object is already being cleaned up.
        if (val == 0) return;
    }
    if (oldValue == 1) {
        const ty = if (header.type == null) {
            log.warn("object with no type leaked, pointer=0x{x}", .{@intFromPtr(obj)});
            return;
        } else header.type.?;

        // set the `delete_in_progress` flag
        if (header.flags.set(.delete_in_progress, .acquire) == true) return;

        _ = if (ty.vtable.deinit) |deinit_cb| deinit_cb(obj);

        // the object was rescued, return instead of deleting.
        if (header.ptr_count.load(.seq_cst) > 0) {
            // unset the `delete_in_progress` flag (asserting that it was set) and returns.
            std.debug.assert(header.flags.unset(.delete_in_progress, .release));
            return;
        }

        // TODO: defered freeing.
        heap.allocator.free(header.allocation());
    }
}

pub export var ObObjectType: ?*Type = null;

pub fn createType(name: []const u8, size: usize, vtable: BaseVTable) !*Type {
    const ty = try allocate(Type, ObObjectType, @sizeOf(Type), name);
    ty.* = .{
        .instance_count = .init(0),
        .size = size,
        .vtable = vtable,
    };
    return ty;
}

pub fn initObjectTypes() !void {
    ObObjectType = try createType("Object Type", @sizeOf(Type), .{});
    getHeader(@ptrCast(ObObjectType)).type = ObObjectType;

    try registerKnownType(.thread, @import("kmod").Thread);
    try registerKnownType(.process, @import("kmod").Process);
    try registerKnownType(.device, @import("kmod").Device);
    try registerKnownType(.driver, @import("kmod").Driver);
    try registerKnownType(.hwio, @import("kmod").HardwareIo);

}

pub const KnownTypeInstance = struct {
    name: []const u8,
    base_vtable: BaseVTable = .{ .deinit = null },
    private: ?*Type = null,

    pub fn getPointer(self: *const KnownTypeInstance) *Type {
        return self.private orelse std.debug.panic("object type \"{s}\" not registered", .{self.name});
    }
};

pub inline fn registerKnownType(comptime tag: @TypeOf(.enum_literal), comptime T: type) !void {
    _ = tag;

    if (!@hasDecl(T, "knownObjectType")) @compileError("invalid known object type");

    const knownType: *KnownTypeInstance = &@field(T, "knownObjectType");

    knownType.private = try createType(knownType.name, @sizeOf(T), knownType.base_vtable);

    // DONE
}

pub const Flags = packed struct(u32) {
    frozen: bool = false,
    delete_in_progress: bool = false,
    _: u30 = 0,
};

pub const Header = extern struct {
    _: void align(0x10) = undefined,
    type: ?*Type,
    size: usize,
    auxilliary_size: usize,
    flags: extern union {
        typed: Flags,
        atomic: std.atomic.Value(u32),

        pub fn set(self: *@This(), comptime flag: std.meta.FieldEnum(Flags), comptime order: std.builtin.AtomicOrder) bool {
            return self.atomic.bitSet(@bitOffsetOf(Flags, @tagName(flag)), order) == 1;
        }

        pub fn unset(self: *@This(), comptime flag: std.meta.FieldEnum(Flags), comptime order: std.builtin.AtomicOrder) bool {
            return self.atomic.bitReset(@bitOffsetOf(Flags, @tagName(flag)), order) == 1;
        }
    },
    ptr_count: std.atomic.Value(u64),
    handle_count: std.atomic.Value(u64),
    name_len: usize,

    pub fn allocation(self: *Header) []u8 {
        const base: [*]u8 = @ptrCast(self);
        return base[0..(@sizeOf(Header) + self.size + self.auxilliary_size)];
    }
};
