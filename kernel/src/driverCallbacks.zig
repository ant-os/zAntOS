//! Driver Callbacks

const std = @import("std");
const driverManager = @import("driverManager.zig");
const filesystem = @import("filesystem.zig");

const DriverObject = driverManager.DriverObject;
const ANTSTATUS = @import("status.zig").Status;

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

/// called to open the file with given name.
pub const FS_OPEN: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(8),
    .signature = fn (*const DriverObject, [*]const u8, usize, **anyopaque) callconv(.c) ANTSTATUS,
};

pub const FS_CLOSE: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(9),
    .signature = fn (*const DriverObject, *anyopaque) callconv(.c) ANTSTATUS,
};

pub const FS_GET_FILE_INFO: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(10),
    .signature = fn (*const DriverObject, *anyopaque, *filesystem.FileInfo) callconv(.c) ANTSTATUS,
};

pub const FS_SEEK: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(11),
    .signature = fn (*const DriverObject, *anyopaque, usize) callconv(.c) ANTSTATUS,
};

pub const FS_READ: Callback = .{
    .driver_ty = .filesystem,
    .idx = index(12),
    .signature = fn (*const DriverObject, *anyopaque, [*]u8, usize) callconv(.c) ANTSTATUS,
};
