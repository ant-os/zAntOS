const std = @import("std");
const ANTSTATUS = @import("status.zig").Status;

const DriverObject = extern struct {
    parameter_mask: u32,
    parameter_blocK: *anyopaque,
    version: u32,
};

const FilesystemDriver = struct {
    driver_object: *DriverObject,
    callbacks: Callbacks,

    const Callbacks = struct {
        open: *const fn (*const DriverObject, *const [255]u8, **anyopaque) callconv(.c) ANTSTATUS,
        read: *const fn (*const DriverObject, *anyopaque, *u8, usize, usize) callconv(.c) ANTSTATUS,
        close: *const fn (*const DriverObject, *anyopaque) callconv(.c) ANTSTATUS,
    };
};
