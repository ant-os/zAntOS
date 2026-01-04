const std = @import("std");
const ANTSTATUS = @import("status.zig").Status;
const HANDLE = @import("types.zig").HANDLE;
const driverManager = @import("driverManager.zig");
const driverCallbacks = @import("driverCallbacks.zig");
const resource = @import("resource.zig");
const heap = @import("heap.zig");

pub const max_filename_len = 255;

pub const FileInfo = extern struct {
    name: [max_filename_len]u8,
    name_len: u8,
    size: u64,
    offset: u64,
    flags: packed struct(u8) {
        readonly: bool,
        hidden: bool,
        system: bool,
        link: bool,
        reserved: u4 = 0,
    },
};

pub fn mount(h_driver: HANDLE, backing_dev: HANDLE, param_keys: [*]u8, param_values: [*]u64) !HANDLE {
    const driver = h_driver.asDriver() orelse return error.InvalidHandle;

    if (backing_dev.type != .device) return error.InvalidHandle;

    const cb = driver.callback(driverCallbacks.FS_MOUNT);

    if (cb == null) return error.UnsupportedOperation;

    var desc: *anyopaque = undefined;
    try cb.?(driver.object, backing_dev, param_keys, param_values, &desc).intoZigError();

    return try resource.create(driver, .{ .device = .filesystem }, desc);
}

pub fn open(fs_handle: HANDLE, name: []const u8) !HANDLE {
    if (fs_handle.type != .device or fs_handle.type.device != .filesystem) return error.InvalidHandle;

    const open_cb = fs_handle.owner.callback(driverCallbacks.FS_OPEN);

    if (open_cb == null) return error.UnsupportedOperation;

    var desc: *anyopaque = undefined;
    try open_cb.?(fs_handle.owner.object, fs_handle.internal, name.ptr, name.len, &desc).intoZigError();

    return try resource.create(fs_handle.owner, .file, desc);
}

pub fn closeNoDestroy(h_file: HANDLE) !void {
    if (h_file.type != .device or h_file.type.device != .filesystem) return error.InvalidHandle;

    const close_cb = h_file.owner.callback(driverCallbacks.FS_CLOSE);

    if (close_cb == null) return error.UnsupportedOperation;

    try close_cb.?(h_file.owner.object, h_file.internal).intoZigError();
}

pub fn getfileinfo(driver: *const driverManager.DriverDesciptor, desc: *anyopaque) !*const FileInfo {
    if (driver.type_ != .filesystem) return error.MismatchedDriverType;

    const getfileinfo_cb = driver.callback(driverCallbacks.FS_GET_FILE_INFO);

    if (getfileinfo_cb == null) return error.UnsupportedOperation;

    const info = try heap.allocator.create(FileInfo);
    try getfileinfo_cb.?(driver.object, desc, info).intoZigError();

    return info;
}

pub fn read(
    driver: *const driverManager.DriverDesciptor,
    drv_internal_handle: *anyopaque,
    buffer: []u8,
) !void {
    if (driver.type_ != .filesystem) return error.MismatchedDriverType;

    const read_cb = driver.callback(driverCallbacks.FS_READ);

    if (read_cb == null) return error.UnsupportedOperation;

    try read_cb.?(driver.object, drv_internal_handle, buffer.ptr, buffer.len).intoZigError();
}
