const std = @import("std");
const driverManager = @import("driverCallbacks.zig");
const device = @import("resource.zig");

pub const HANDLE = *const device.ResourceDescriptor;
pub const ANTSTATUS = @import("status.zig").Status;
