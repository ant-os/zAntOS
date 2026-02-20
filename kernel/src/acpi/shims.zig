//! Shims for uACPI
//!


const uacpi = @import("zuacpi").uacpi;
const std = @import("std");
const bootboot = @import("../bootboot.zig");
const binder = @import("zuacpi.zig");

const cc = std.builtin.CallingConvention.c;

const log = std.log.scoped(.uacpi);

fn trace(comptime src: std.builtin.SourceLocation, args: anytype) void {
    log.debug("TRACE {s} with args {any}", .{ src.fn_name, args });
}

pub export fn uacpi_kernel_map(addr: *u8, len: usize) callconv(cc) ?*u8 {
    trace(@src(), .{ addr, len });
    return addr;
}

export fn uacpi_kernel_unmap(addr: [*]u8, len: usize) callconv(cc) void {
    trace(@src(), .{ addr, len });
}

pub export fn uacpi_kernel_get_rsdp(addr: *u64) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    
    addr.* = binder.get_rsdp();
    return .ok;
}

export fn uacpi_kernel_pci_device_open(
    addr: uacpi.PciAddress,
    out_handle: **anyopaque,
) callconv(cc) uacpi.uacpi_status {
    _ = out_handle;
    trace(@src(), .{addr});
    return .unimplemented;
}

comptime {
    for (&.{ u8, u16, u32 }) |T| {
        const S = struct {
            pub fn ir(handle: u16, offset: usize, ret: *T) callconv(cc) uacpi.uacpi_status {
                _ = ret;
                trace(@src(), .{handle, offset});
                return .unimplemented;
            }
            pub fn iw(handle: u16, offset: usize, value: T) callconv(cc) uacpi.uacpi_status {
                trace(@src(), .{handle, offset, value});
                return .unimplemented;
            }
            pub fn pr(address: *anyopaque, offset: usize, ret: *T) callconv(cc) uacpi.uacpi_status {
                  _ = ret;
                trace(@src(), .{address, offset});
                return .unimplemented;
            }
            pub fn pw(address: *anyopaque, offset: usize, value: T) callconv(cc) uacpi.uacpi_status {
                trace(@src(), .{address, offset, value});
                return .unimplemented;
            }
        };

        @export(&S.ir, .{ .name = std.fmt.comptimePrint("uacpi_kernel_io_read{d}", .{@bitSizeOf(T)}) });
        @export(&S.iw, .{ .name = std.fmt.comptimePrint("uacpi_kernel_io_write{d}", .{@bitSizeOf(T)}) });
        @export(&S.pr, .{ .name = std.fmt.comptimePrint("uacpi_kernel_pci_read{d}", .{@bitSizeOf(T)}) });
        @export(&S.pw, .{ .name = std.fmt.comptimePrint("uacpi_kernel_pci_write{d}", .{@bitSizeOf(T)}) });
    }
}

export fn uacpi_kernel_pci_device_close(_: usize) void {
    trace(@src(), .{});
}

export fn uacpi_kernel_io_map(port: uacpi.IoAddress, _: usize, _: *u16) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{port});
    return .unimplemented;
}

export fn uacpi_kernel_io_unmap(_: *u16) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    return .unimplemented;
}

export fn uacpi_kernel_get_thread_id() callconv(cc) ?*anyopaque {
    trace(@src(), .{});
    return null;
}

export fn uacpi_kernel_get_nanoseconds_since_boot() callconv(cc) u64 {
    trace(@src(), .{});
    return 0;
}

export fn uacpi_kernel_stall(usec: u8) callconv(cc) void {
    trace(@src(), .{usec});
}

export fn uacpi_kernel_sleep(msec: u64) callconv(cc) void {
    trace(@src(), .{msec});
}

var __dummy: u8 = 0;
export fn uacpi_kernel_create_mutex() callconv(cc) ?*anyopaque {
    trace(@src(), .{});
    return @ptrCast(&__dummy);
}

export fn uacpi_kernel_free_mutex(ptr: *anyopaque) callconv(cc) void {
    trace(@src(), .{ptr});
}

export fn uacpi_kernel_acquire_mutex(mutex: *anyopaque, timeout: u16) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{ .ptr = mutex, .timeout = timeout });

    return .ok;
}

export fn uacpi_kernel_release_mutex(mutex: *anyopaque) callconv(cc) void {
    trace(@src(), .{mutex});
}

export fn uacpi_kernel_create_event() callconv(cc) ?*anyopaque {
    trace(@src(), .{});

    return @ptrCast(&__dummy);
}

export fn uacpi_kernel_free_event(ptr: *anyopaque) callconv(cc) void {
    trace(@src(), .{ptr});
}

export fn uacpi_kernel_wait_for_event(sema: *anyopaque, timeout: u16) callconv(cc) bool {
    trace(@src(), .{ sema, timeout });
    return false;
}

export fn uacpi_kernel_signal_event(_: *anyopaque) callconv(cc) void {
    trace(@src(), .{});
}

export fn uacpi_kernel_reset_event(_: *anyopaque) callconv(cc) void {
    trace(@src(), .{});
}

export fn uacpi_kernel_handle_firmware_request(_: [*c]uacpi.FirmwareRequestRaw) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    return .unimplemented;
}

export fn uacpi_kernel_install_interrupt_handler(gsi: u32, _: uacpi.InterruptHandler, _: ?*anyopaque, _: **anyopaque) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{ .gsi = gsi });
    return .unimplemented;
}

export fn uacpi_kernel_uninstall_interrupt_handler(_: uacpi.InterruptHandler, _: *anyopaque) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    return .unimplemented;
}

export fn uacpi_kernel_create_spinlock() callconv(cc) ?*anyopaque {
    trace(@src(), .{});
    
    return @ptrCast(&__dummy);
}

export fn uacpi_kernel_free_spinlock(ptr: *anyopaque) callconv(cc) void {
    trace(@src(), .{ptr});
}

export fn uacpi_kernel_lock_spinlock(lock: *anyopaque) callconv(cc) u8 {
    trace(@src(), .{lock});

    return 0;
}

export fn uacpi_kernel_unlock_spinlock(lock: *anyopaque, state: u8) callconv(cc) void {
    trace(@src(), .{ lock, state });
}

export fn uacpi_kernel_schedule_work(_: uacpi.WorkType, _: uacpi.WorkHandler, _: ?*anyopaque) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    return .unimplemented;
}

export fn uacpi_kernel_wait_for_work_completion() callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    return .unimplemented;
}
