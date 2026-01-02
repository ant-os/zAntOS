const std = @import("std");
const ANTSTATUS = @import("status.zig").Status;
const driverManager = @import("driverManager.zig");
const driverCallbacks = @import("driverCallbacks.zig");
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

pub fn open(driver: *const driverManager.DriverDesciptor, name: []const u8) !*anyopaque {
    if (driver.type_ != .filesystem) return error.MismatchedDriverType;

    const open_cb = driver.callback(driverCallbacks.FS_OPEN);

    if (open_cb == null) return error.UnsupportedOperation;

    var desc: *anyopaque = undefined;
    try open_cb.?(driver.object, name.ptr, name.len, &desc).intoZigError();

    return desc;
}
pub fn close(driver: *const driverManager.DriverDesciptor, desc: *anyopaque) !void {
    if (driver.type_ != .filesystem) return error.MismatchedDriverType;

    const close_cb = driver.callback(driverCallbacks.FS_CLOSE);

    if (close_cb == null) return error.UnsupportedOperation;

    try close_cb.?(driver.object, desc).intoZigError();
}

pub fn getfileinfo(driver: *const driverManager.DriverDesciptor, desc: *anyopaque) !*const FileInfo {
    if (driver.type_ != .filesystem) return error.MismatchedDriverType;

    const getfileinfo_cb = driver.callback(driverCallbacks.FS_GET_FILE_INFO);

    if (getfileinfo_cb == null) return error.UnsupportedOperation;

    const info = try heap.allocator.create(FileInfo);
    try getfileinfo_cb.?(driver.object, desc, info).intoZigError();

    return info;
}

pub fn read(driver: *const driverManager.DriverDesciptor, desc: *anyopaque, buffer: []u8) !void {
    if (driver.type_ != .filesystem) return error.MismatchedDriverType;

    const read_cb = driver.callback(driverCallbacks.FS_READ);

    if (read_cb == null) return error.UnsupportedOperation;

    try read_cb.?(driver.object, desc, buffer.ptr, buffer.len).intoZigError();
}
