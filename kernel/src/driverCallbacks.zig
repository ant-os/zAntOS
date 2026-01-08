//! Driver Callbacks

const std = @import("std");
const driverManager = @import("driverManager.zig");
const filesystem = @import("filesystem.zig");
const blockdev = @import("blockdev.zig");

const DriverObject = driverManager.DriverObject;
const HANDLE = @import("types.zig").HANDLE;
const ANTSTATUS = @import("status.zig").ANTSTATUS;

/// Maximum index for a driver callback, the driver object contains a fixes size array of the size of this value plus one.
pub const MAXIMUM_INDEX = 31;

/// Validation function for an index that causes a compiler error if the index is larger than `MAXIMUM_INDEX`.
inline fn index(comptime idx: u8) u8 {
    comptime if (idx > MAXIMUM_INDEX) {
        @compileError(std.fmt.comptimePrint("driver callback index of {d} is larger than maximum index of {d}", .{
            idx,
            MAXIMUM_INDEX,
        }));
    };

    return idx;
}

pub const Callback = struct {
    idx: u8,
    driver_ty: driverManager.DriverType,
    signature: type,
};

/// called on driver removal.
pub const DELETE: Callback = .{
    .driver_ty = .generic,
    .idx = index(1),
    .signature = fn (*DriverObject) callconv(.c) ANTSTATUS,
};

pub const FS_MOUNT: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(6),
    .signature = fn (
        driver_object: *const DriverObject,
        params: driverManager.SimpleKVPairs,
        out_handler: **anyopaque,
    ) callconv(.c) ANTSTATUS,
};

pub const FS_UNMOUNT: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(7),
    .signature = fn (*const DriverObject, *anyopaque) callconv(.c) ANTSTATUS,
};

pub const FS_OPEN: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(8),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        [*]const u8,
        usize,
        **anyopaque,
    ) callconv(.c) ANTSTATUS,
};

pub const FS_CLOSE: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(9),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
    ) callconv(.c) ANTSTATUS,
};

pub const FS_GET_FILE_INFO: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(10),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        *filesystem.FileInfo,
    ) callconv(.c) ANTSTATUS,
};

pub const FS_SEEK: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(11),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        usize,
    ) callconv(.c) ANTSTATUS,
};

pub const FS_READ: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(12),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        [*]u8,
        usize,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_ATTACH: Callback = .{
    .driver_ty = .block,
    .idx = index(6),
    .signature = fn (
        *const DriverObject,
        params: driverManager.SimpleKVPairs,
        **anyopaque,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_DETACH: Callback = .{
    .driver_ty = .block,
    .idx = index(7),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_GET_INFO: Callback = .{
    .driver_ty = .block,
    .idx = index(8),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        *blockdev.Info,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_READ: Callback = .{
    .driver_ty = .block,
    .idx = index(9),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        sector: u64,
        num_sectors: usize,
        [*]u8,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_WRITE: Callback = .{
    .driver_ty = .block,
    .idx = index(10),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        sector: u64,
        num_sectors: usize,
        [*]u8,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_MAP: Callback = .{
    .driver_ty = .block,
    .idx = index(12),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        sector: u64,
        num_sectors: u64,
        *[*]u8,
    ) callconv(.c) ANTSTATUS,
};

pub const BLOCK_UNMAP: Callback = .{
    .driver_ty = .block,
    .idx = index(13),
    .signature = fn (
        *const DriverObject,
        *anyopaque,
        num_sectors: u64,
        [*]u8,
    ) callconv(.c) ANTSTATUS,
};
