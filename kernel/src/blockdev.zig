//! Block Device

const HANDLE = @import("types.zig").HANDLE;
const ANTSTATUS = @import("status.zig").ANTSTATUS;
const callbacks = @import("driverCallbacks.zig");
const DriverDesc = @import("driverManager.zig").DriverDescriptor;
const SimpleKVPairs = @import("driverManager.zig").SimpleKVPairs;
const resource = @import("resource.zig");

pub const Info = extern struct {
    sector_size: u16,
    sector_count: u64,
};

const BlockDevice = @This();

handle: HANDLE,

pub fn attach(
    driver_handle: HANDLE,
    parameters: SimpleKVPairs,
    out_status: ?*ANTSTATUS,
) ANTSTATUS.ZigError!BlockDevice {
    const driver = driver_handle.asDriver() orelse return error.InvalidHandle;

    const attach_cb = driver.callback(callbacks.BLOCK_ATTACH) orelse return error.UnsupportedOperation;

    var handle: *anyopaque = undefined;
    const status = attach_cb(driver.object, parameters, &handle);

    // optionally preserve raw status as intoZigError() is lossy.
    if (out_status) |s| {
        s.* = status;
    }

    try status.intoZigError();

    return .{
        .handle = try resource.create(driver, .{ .device = .block }, handle),
    };
}

pub fn mapSectors(
    self: BlockDevice,
    sector: u64,
    num_sectors: u64,
    out_status: ?*ANTSTATUS,
) ANTSTATUS.ZigError![*]u8 {
    if (self.handle.type != .device or self.handle.type.device != .block) return error.InvalidHandle;
    if (self.handle.internal == null or self.handle.owner == null) return error.InvalidHandle;

    const attach_cb = self.handle.owner.?.callback(callbacks.BLOCK_MAP) orelse return error.UnsupportedOperation;

    var addr: [*]u8 = undefined;
    const status = attach_cb(
        self.handle.owner.?.object,
        self.handle.internal.?,
        sector,
        num_sectors,
        &addr,
    );

    // optionally preserve raw status as intoZigError() is lossy.
    if (out_status) |s| s.* = status;

    try status.intoZigError();

    return addr;
}
