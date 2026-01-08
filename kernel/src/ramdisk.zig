const std = @import("std");
const DriverObject = @import("driverManager.zig").DriverObject;
const Parameters = @import("driverManager.zig").SimpleKVPairs;
const ANTSTATUS = @import("status.zig").ANTSTATUS;
const klog = std.log.scoped(.ramdisk_driver);
const driverCallbacks = @import("driverCallbacks.zig");
const heap = @import("heap.zig");

const A: [*]u8 = "base\xFFsize\xFF\x00";

pub fn init(drv: *DriverObject) callconv(.c) ANTSTATUS {
    drv.setCallback(driverCallbacks.BLOCK_ATTACH, &attach);
    drv.setCallback(driverCallbacks.BLOCK_READ, &read);
    drv.setCallback(driverCallbacks.BLOCK_MAP, &map);

    return .SUCCESS;
}

pub const RamdiskConfig = struct {
    base: [*]u8,
    size: u64,
    readonly: bool = true,
    sectorsize: u64 = 0x1000,
};

pub fn attach(
    drv: *const DriverObject,
    r_params: Parameters,
    out_handle: **anyopaque,
) callconv(.c) ANTSTATUS {
    _ = drv;

    klog.debug("TRACE: attach({f})", .{r_params});

    const params = r_params.parseInto(struct {
        base: [*]u8,
        size: u64,
        readonly: bool = true,
        sectorsize: u64 = 0x1000,
    }) catch |e| return .fromZigError(e);

    klog.debug("ram disk config is {any}", .{params});

    const config = heap.allocator.create(RamdiskConfig) catch return .err(.out_of_memory);

    config.* = RamdiskConfig{
        .base = params.base,
        .size = params.size,
    };

    out_handle.* = config;

    return .SUCCESS;
}

pub fn read(
    _: *const DriverObject,
    r_dev: *anyopaque,
    sector: u64,
    num_sectors: u64,
    buffer: [*]u8,
) callconv(.c) ANTSTATUS {
    const dev: *const RamdiskConfig = @ptrCast(@alignCast(r_dev));

    _ = dev;
    _ = sector;
    _ = num_sectors;
    _ = buffer;

    return .err(.not_yet_implemented);
}

// BLOCK_MAP, BLOCK_UNMAP.
pub fn map(
    drv: *const DriverObject,
    r_dev: *anyopaque,
    sector: u64,
    num_sectors: u64,
    out_addr: *[*]u8,
) callconv(.c) ANTSTATUS {
    _ = drv;

    const dev: *const RamdiskConfig = @ptrCast(@alignCast(r_dev));

    klog.debug("TRACE: map(<ramdisk at {any}> sector: {d}, num_sectors: {d})", .{
        dev.base,
        sector,
        num_sectors,
    });

    if (num_sectors > (dev.size / dev.sectorsize)) return .err(.out_of_bounds);

    const start = sector * dev.sectorsize;

    out_addr.* = dev.base[start..];

    return .SUCCESS;
}

pub fn unmap(
    drv: *const DriverObject,
    r_dev: *anyopaque,
    num_sectors: u64,
    addr: [*]u8,
) callconv(.c) ANTSTATUS {
    _ = drv;
    _ = r_dev;
    _ = num_sectors;
    _ = addr;

    return .SUCCESS;
}
