const std = @import("std");
const ANTSTATUS = @import("status.zig").Status;
const heap = @import("heap.zig");
const filesystem = @import("filesystem.zig");
const callbacks = @import("driverCallbacks.zig");
pub const DriverObject = extern struct {
    name: [255]u8,
    paramter_count: u64,
    paramter_values: ?[*]const ParameterDesc,
    callbacks: [callbacks.MAXIMUM_INDEX + 1]usize,

    pub inline fn setCallback(
        self: *DriverObject,
        comptime cb: callbacks.Callback,
        func: *const cb.signature,
    ) void {
        self.callbacks[cb.idx] = @intFromPtr(func);
    }
};

pub const ParameterDesc = extern struct {
    name: [*]const u8,
    name_len: u32,
    value: u64,

    pub fn new(name: []const u8, value: u64) ParameterDesc {
        return .{
            .name = name.ptr,
            .name_len = @intCast(name.len),
            .value = value,
        };
    }

    pub inline fn getName(self: ParameterDesc) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const DriverType = enum {
    generic,
    filesystem,
};

pub const DriverInitFunc = fn (*DriverObject) callconv(.c) ANTSTATUS;

pub const DriverDesciptor = struct {
    node: std.DoublyLinkedList.Node,
    object: *DriverObject,
    init_func: *const DriverInitFunc,
    type_: DriverType,

    pub fn init(self: *const DriverDesciptor) !void {
        try self.init_func(self.object).intoZigError();
    }

    pub fn setCallback(
        self: *const DriverDesciptor,
        comptime cb: callbacks.Callback,
        func: *const cb.signature,
    ) !void {
        if (cb.driver_ty != .generic and cb.driver_ty != self.type_)
            return error.InvalidParameter;

        self.object.setCallback(cb, func);
    }

    pub inline fn callback(
        self: *const DriverDesciptor,
        comptime cb: callbacks.Callback,
    ) ?*const cb.signature {
        if (cb.driver_ty != .generic and cb.driver_ty != self.type_) return null;

        return @ptrFromInt(self.object.callbacks[cb.idx]);
    }
};

var driver_nodes: std.DoublyLinkedList = .{};
var drivers: u32 = 0;

var empty_params = [0]ParameterDesc{};

pub inline fn toParameters(param_block: anytype) []ParameterDesc {
    const param_count = @typeInfo(param_block).@"struct".fields;
    if (param_count == 0) return empty_params[0..];

    var params: [param_count]ParameterDesc = undefined;

    inline for (@typeInfo(param_block).@"struct".fields, 0..) |field, idx| {
        params[idx] = .{
            .name = undefined,
            .name_len = field.name.len,
            .value = @bitCast(@field(param_block, field.name)),
        };
    }

    return params;
}

pub fn register(
    name: []const u8,
    type_: DriverType,
    init_fn: *const DriverInitFunc,
    paramters: ?[*]const ParameterDesc,
    param_count: usize,
) !*const DriverDesciptor {
    var desc = try heap.allocator.create(DriverDesciptor);

    desc.* = std.mem.zeroInit(DriverDesciptor, desc.*);

    desc.object = try heap.allocator.create(DriverObject);
    desc.object.* = std.mem.zeroInit(DriverObject, desc.object.*);
    desc.type_ = type_;
    std.mem.copyForwards(u8, &desc.object.name, name);
    if (paramters != null and param_count != 0) {
        desc.object.paramter_count = @intCast(param_count);
        desc.object.paramter_values = paramters;
    }
    desc.init_func = init_fn;
    drivers += 1;

    driver_nodes.append(&desc.node);

    return @ptrCast(desc);
}
