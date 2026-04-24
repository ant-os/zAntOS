//! Object
//!

const std = @import("std");
const arch = @import("../hal/arch/arch.zig");
const heap = @import("kmod").heap;
const log = std.log.scoped(.object_manager);
const antk_c = @import("../antk/antk.zig").c;
const antk = @import("../antk/antk.zig");
const pathutils = @import("../utils/path.zig");

pub const Vode = @import("vode.zig");

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

pub fn allocateFreestanding(comptime T: type, @"type": ?*Type, size_: usize, auxiliary_size: usize, attributes: ?u32) !*T {
    const size = @max(if (T != anyopaque) @sizeOf(T) else 0, if (@"type" != null) @"type".?.size else 0, std.mem.alignForward(usize, size_, 0x10));
    const allocationSize = @sizeOf(Header) + size + auxiliary_size;
    const allocation = try heap.allocator.alignedAlloc(u8, .@"16", allocationSize);
    @memset(allocation, 0);
    const header: *Header = @ptrCast(allocation.ptr);
    const body: *T = @ptrFromInt(@intFromPtr(allocation.ptr) + @sizeOf(Header));

    if (@"type" != null) referenceRaw(@ptrCast(@"type"));

    header.* = .{
        .type = @"type",
        .size = size,
        .auxilliary_size = auxiliary_size,
        .ptr_count = .init(1),
        .handle_count = .init(0),
        .flags = .{ .typed = .{} },
        .name_len = 0,
        .attributes = attributes orelse 0,
    };

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
    log.debug("ref(header={any}, ty={any})", .{ getHeader(obj), ty });
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
    _ = unreferenceRaw(@ptrCast(obj));
}

pub fn unrefObjectMustNotDelete(comptime T: type, obj: *T) void {
    if (unreferenceRaw(@ptrCast(obj))) @panic("internal error: unexpected object deletion");
}

pub fn unreferenceRaw(obj: *anyopaque) bool {
    const header = getHeader(obj);
    var oldValue: u64 = 1;
    while (header.ptr_count.cmpxchgWeak(
        oldValue,
        oldValue - 1,
        .seq_cst,
        .monotonic,
    )) |val| : (oldValue = val) {
        // the object is already being cleaned up.
        if (val == 0) return false;
    }
    if (oldValue == 1) {
        const ty = if (header.type == null) {
            log.warn("object with no type leaked, pointer=0x{x}", .{@intFromPtr(obj)});
            return true;
        } else header.type.?;

        // set the `delete_in_progress` flag
        if (header.flags.set(.delete_in_progress, .acquire) == true) return false;

        _ = if (ty.vtable.deinit) |deinit_cb| deinit_cb(obj);

        // the object was rescued, return instead of deleting.
        if (header.ptr_count.load(.seq_cst) > 0) {
            // unset the `delete_in_progress` flag (asserting that it was set) and returns.
            std.debug.assert(header.flags.unset(.delete_in_progress, .release));
            return false;
        }

        // TODO: defered freeing.
        heap.allocator.free(header.allocation());

        return true;
    }

    return false;
}

pub export var ObObjectType: ?*Type = null;

pub fn createVode(
    directory: ?*Vode,
    path: []const u8,
    kernel_mode: bool,
    modedata: Vode.Modedata,
) !*Vode {
    _ = kernel_mode;

    const basename = pathutils.basename(path) orelse return error.InvalidPath;
    const dirname = pathutils.dirname(path);

    log.debug("creating vode with dirname=\"{s}\" and realname=\"{s}\"", .{ dirname, basename });

    var remainingString: []const u8 = &.{};
    const dir = if (directory) |dir| try dir.lookupRelative(
        dirname,
        antk_c.OB_VODE_OPEN,
        &remainingString,
    ) else try Vode.lookupAbsolute(
        dirname,
        antk_c.OB_VODE_OPEN,
        &remainingString,
    );

    if (remainingString.len > 0) return error.NotFound;

    return try dir.insert(basename, modedata);
}

pub fn createUnnamedType(size: usize, vtable: BaseVTable) !*Type {
    const ty = try allocateFreestanding(
        Type,
        ObObjectType,
        @sizeOf(Type),
        0,
        null,
    );

    ty.* = .{
        .instance_count = .init(0),
        .size = size,
        .vtable = vtable,
    };
    return ty;
}

pub fn createObject(
    comptime T: type,
    type_: *Type,
    size_override: ?usize,
    kernel: bool,
    directory: ?*Vode,
    name: ?[]const u8,
    attributes: ?u32,
    out_vode: ?**Vode,
) !*T {
    if (T == anyopaque and size_override == null) return error.InvalidParameter;
    if (name != null and out_vode != null) return error.InvalidParameter;

    errdefer |e| log.debug(
        "createObject() failed with: {s}",
        .{@errorName(e)},
    );

    const object = try allocateFreestanding(
        T,
        type_,
        if (T != anyopaque and size_override == null) @sizeOf(T) else size_override.?,
        0,
        attributes,
    );

    errdefer unreferenceObject(T, object);

    if (name != null) {
        const vode = try createVode(
            directory,
            name.?,
            kernel,
            .{ .object = @ptrCast(object) },
        );

        if (out_vode) |loc| loc.* = vode;
    }

    return object;
}

pub var typeDirectory: ?*Vode = null;

inline fn panicUninit() void {
    @panic("system not initialized");
}

pub fn createType(name: []const u8, size: usize, vtable: BaseVTable) !*Type {
    const ty = try createObject(
        Type,
        ObObjectType orelse panicUninit(),
        null,
        true,
        typeDirectory,
        name,
        null,
        null,
    );

    ty.* = .{
        .instance_count = .init(0),
        .size = size,
        .vtable = vtable,
    };
    return ty;
}

/// associate a path with an object by create a vode pointing to it.
/// NOTE: The VODE lives as long as the object, it does NOT increment the object refcount.
pub fn associateObjectPath(comptime T: type, directory: ?*Vode, path: []const u8, object: *T) !void {
    if (getHeader(@ptrCast(object)).vode.load(.seq_cst) != null) return error.AlreadyExists;

    const vode = try createVode(
        directory,
        path,
        true,
        .{ .object = object },
    );

    // the object passed internally holds a reference
    unrefObjectMustNotDelete(Vode, vode);
}

pub fn init() !void {
    ObObjectType = try createUnnamedType(@sizeOf(Type), .{});
    getHeader(@ptrCast(ObObjectType)).type = ObObjectType;

    Vode.knownObjectType.private = try createUnnamedType(
        @sizeOf(Vode),
        Vode.knownObjectType.base_vtable,
    );

    try Vode.init();
    defer Vode.lateInit() catch |e| std.debug.panic(
        "failed to finalize virtual filesystem: {s}",
        .{@errorName(e)},
    );

    typeDirectory = try createVode(
        null,
        "//ObjectTypes",
        true,
        .container,
    );

    _ = try typeDirectory.?.insert(
        "ObjectType",
        .{ .object = ObObjectType.? },
    );

    _ = try typeDirectory.?.insert(
        "Vode",
        .{ .object = Vode.knownObjectType.getPointer() },
    );

    try registerKnownType(.mutex, @import("kmod").Mutex);
    try registerKnownType(.thread, @import("kmod").Thread);
    try registerKnownType(.process, @import("kmod").Process);
    try registerKnownType(.device, @import("kmod").Device);
    try registerKnownType(.driver, @import("kmod").Driver);
    try registerKnownType(.hwio, @import("kmod").HardwareIo);
}

pub fn referenceObjectByName(
    path: []const u8,
    desiredAccess: antk_c.ACCESS_MASK,
    kernelMode: bool,
    @"type": ?*Type,
    flags: Vode.Flags,
    remaining_path: ?*[]const u8,
) !*anyopaque {
    var _dummy_remaining_path: []const u8 = &.{};

    const node = try Vode.lookupAbsolute(
        path,
        flags | antk_c.OB_VODE_OPEN,
        remaining_path orelse &_dummy_remaining_path,
    );
    if ((flags & antk_c.OB_VODE_OPEN) != 0) return @ptrCast(node);

    defer unreferenceObject(Vode, node);

    if (remaining_path == null and _dummy_remaining_path.len != 0)
        return error.MoreProcessingRequired;

    // NOTE: for now just stub out the access checks rights/etc.
    if (!kernelMode) log.warn("usermode access checks are not yet implemented", .{});
    _ = desiredAccess;

    if (node.mode != .object) return error.InvalidPath;
    if (node.mode.object == null) return error.NoAssociatedObject;

    if (@"type") |ty| try referenceObject(
        node.mode.object.?,
        ty,
    ) else referenceRaw(node.mode.object.?);

    return node.mode.object.?;
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
    vode: std.atomic.Value(?*Vode) = .init(null),
    attributes: u32,

    pub fn allocation(self: *Header) []u8 {
        const base: [*]u8 = @ptrCast(self);
        return base[0..(@sizeOf(Header) + self.size + self.auxilliary_size)];
    }
};
