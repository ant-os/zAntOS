const std = @import("std");
const heap = @import("heap.zig");
const filesystem = @import("filesystem.zig");
const root = @import("root");
const ANTSTATUS = root.ANTSTATUS;

const DriverDescriptor = @import("driverManager.zig").DriverDescriptor;
const DriverObject = @import("driverManager.zig").DriverObject;

pub const ChardevSpecialization = enum(u6) {
    generic = 0,
    keyboard = 1,
    mouse = 2,
    _,
};

pub const DeviceCategory = enum(u8) {
    general,
    block,
    filesystem,
    chardev,
};

pub const ResourceType = enum(u8) {
    invalid,
    driver,
    file,
    filesystem,
    directory,
    device,
};

pub const DeviceObject = extern struct {
    category: DeviceCategory = .general,
    type_tag: u8 = 0,
    device_id: u16 = 0,
    vendor_id: u16 = 0,
    private: ?*anyopaque = null,
};

pub const FileObject = extern struct {
    fs_handle: ?*FilesystemObject = null,
    backing_device: ?*DeviceObject = null,
    private: ?*anyopaque = null,
    size: u64 = 0,
    blocks: u64 = 0,
    flags: packed struct(u8) {
        readonly: bool = false,
        system: bool = false,
        hidden: bool = false,
        link: bool = false,
        reserved: u4 = 0,
    } = .{},
    created: u64 = 0,
    updated: u64 = 0,
};

pub const FilesystemObject = extern struct { root_dir_handle: *DirectoryObject, private: ?*anyopaque = null, flags: packed struct(u8) {
    pseudo: bool = false,
    readonly: bool = false,
    reserved: u6 = 0,
} = .{} };

pub const DirectoryObject = extern struct {
    fs_handle: ?*FilesystemObject = null,
    parent: ?*DirectoryObject = null,
    num_entries_hint: u64 = 0,
};

pub const VfsNode = struct {
    navigation: std.DoublyLinkedList.Node,
    parent: ?*ResourceDescriptor,
    name_override: ?[*:0]const u8,
};

pub const ResourceDescriptor = struct {
    owner: ?*root.Executable = null,
    resource_node: std.DoublyLinkedList.Node = .{},

    vfs_node: VfsNode = .{
        .navigation = .{},
        .parent = null,
        .name_override = null,
    },

    object: union(ResourceType) {
        invalid: void,
        driver: DriverDescriptor,
        file: FileObject,
        filesystem: FilesystemObject,
        directory: DirectoryObject,
        device: DeviceObject,
    } = .invalid,

    refcount: u64 = 0,
};

pub fn keAllocateHandle(
    ty: ResourceType,
) !*ResourceDescriptor {
    const desc = try heap.allocator.create(ResourceDescriptor);
    errdefer heap.allocator.destroy(desc);

    switch (ty) {
        .invalid => desc.object = .invalid,
        .driver => {
            const dobj = try heap.allocator.create(DriverObject);
            dobj.* = std.mem.zeroInit(DriverObject, .{});
            desc.object = .{ .driver = .{ .object = dobj } };
        },
        .file => desc.object = .{ .file = .{} },
        .filesystem => {
            const rootdir = try keAllocateHandle(.directory);
            desc.object = .{
                .filesystem = .{ .root_dir_handle = &rootdir.object.directory },
            };
        },
        .directory => desc.object = .{ .directory = .{} },
        .device => desc.object = .{ .device = .{} },
    }

    desc.owner = @constCast(root.Executable.kernel().asManaged());
    desc.owner.?.resources.append(&desc.resource_node);
    desc.owner.?.unmanaged.num_resources += 1;
    desc.refcount = 0;
    desc.vfs_node = .{
        .navigation = .{},
        .parent = null,
        .name_override = null,
    };

    return desc;
}

pub fn create(
    owner: ?*DriverDescriptor,
    ty: ResourceType,
    handle: *anyopaque,
) !*const ResourceDescriptor {
    // if (owner == null and ty == .file) return error.InvalidParameter;

    // var resources = if (owner != null) &owner.?.resources else &global_resources;

    // const desc: *ResourceDescriptor = try heap.allocator.create(ResourceDescriptor);

    // desc.* = .{
    //     .owner = owner,
    //     .internal = handle,
    //     .type = ty,
    //     .node = .{},
    // };

    // resources.append(&desc.node);

    // if (owner != null) owner.?.resource_count += 1 else global_resource_count += 1;

    // return desc;

    _ = owner;
    _ = ty;
    _ = handle;

    @panic("todo");
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

    // deleteResource(desc);
}

// pub fn deleteResource(desc: *ResourceDescriptor) void {
//     const resources = if (desc.isGlobal()) &global_resources else &desc.owner.?.resources;

//     resources.remove(desc);

//     if (desc.isGlobal()) global_resource_count -= 1 else desc.owner.?.resource_count -= 1;

//     heap.allocator.destroy(desc);
// }
