const std = @import("std");
const heap = @import("heap.zig");
const filesystem = @import("filesystem.zig");

const DriverDescriptor = @import("driverManager.zig").DriverDescriptor;

pub const ChardevSpecialization = enum(u6) {
    generic = 0,
    keyboard = 1,
    mouse = 2,
    _,
};

pub const DeviceType = union(enum) {
    generic,
    block,
    filesystem,
    chardev: packed struct(u8) {
        specialization: ChardevSpecialization,
        write: bool,
        read: bool,
    },
};

pub const ResourceType = union(enum) {
    invalid,
    driver,
    file,
    device: DeviceType,
};

pub const ResourceDescriptor = struct {
    owner: ?*DriverDescriptor,
    node: std.DoublyLinkedList.Node,
    internal: ?*anyopaque,
    type: ResourceType,

    pub inline fn isGlobal(self: *const ResourceDescriptor) bool {
        return self.owner == null;
    }

    pub inline fn asDriver(self: *const ResourceDescriptor) ?*DriverDescriptor {
        if (self.type != .driver and self.internal != null) return null;
        return @ptrCast(@alignCast(self.internal));
    }
};

var global_resources: std.DoublyLinkedList = .{};
var global_resource_count: usize = 0;

pub fn create(
    owner: ?*DriverDescriptor,
    ty: ResourceType,
    handle: *anyopaque,
) !*const ResourceDescriptor {
    if (owner == null and ty == .file) return error.InvalidParameter;

    var resources = if (owner != null) &owner.?.resources else &global_resources;

    const desc: *ResourceDescriptor = try heap.allocator.create(ResourceDescriptor);

    desc.* = .{
        .owner = owner,
        .internal = handle,
        .type = ty,
        .node = .{},
    };

    resources.append(&desc.node);

    if (owner != null) owner.?.resource_count += 1 else global_resource_count += 1;

    return desc;
}

pub fn dropResource(desc: *ResourceDescriptor) !void {
    if (desc.type == .file and !desc.isGlobal()) {
        try filesystem.close(desc.owner.?, desc.internal);
    }
    if (desc.type == .driver) {
        // TODO: call DELETE.
    }
    if (desc.type == .device and desc.type.device == .chardev) {
        // TODO: call CHAR_CLOSE
    } else return error.InvalidDescriptor;

    deleteResource(desc);
}

pub fn deleteResource(desc: *ResourceDescriptor) void {
    const resources = if (desc.isGlobal()) &global_resources else &desc.owner.?.resources;

    resources.remove(desc);

    if (desc.isGlobal()) global_resource_count -= 1 else desc.owner.?.resource_count -= 1;

    heap.allocator.destroy(desc);
}
