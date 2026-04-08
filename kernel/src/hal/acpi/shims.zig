//! Shims for uACPI
//!

const uacpi = @import("zuacpi").uacpi;
const std = @import("std");
const bootloader = @import("../../utils/antboot.zig");
const binder = @import("zuacpi.zig");
const mm = @import("../../mm/mm.zig");
const kpcb = @import("kmod").kpcb;
const Thread = @import("kmod").Scheduler.Thread;
const HardwareIo = @import("../../io/abstracthw.zig");
const heap = @import("../../mm/heap.zig");
const SpinLock = @import("../../hal/spinlock.zig").SpinLock;

const cc = std.builtin.CallingConvention.c;

const log = std.log.scoped(.uacpi);

fn trace(comptime src: std.builtin.SourceLocation, args: anytype) void {
    log.debug("TRACE {s} with args {any}", .{ src.fn_name, args });
}

pub export fn uacpi_kernel_map(addr: mm.PhysicalAddress, size: usize) callconv(cc) ?[*]u8 {
    trace(@src(), .{ addr.ptr, size });
    return mm.map(addr, size, .{
        .writable = true,
    }) catch return null;
}

export fn uacpi_kernel_unmap(addr: mm.VirtualAddress, size: usize) callconv(cc) void {
    trace(@src(), .{ addr.ptr, size });
    mm.unmap(addr, size) catch |e| std.debug.panic(
        "uacpi_kernel_unmap(): {s}",
        .{@errorName(e)},
    );
}

pub export fn uacpi_kernel_get_rsdp(addr: *u64) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    addr.* = binder.get_rsdp();
    return .ok;
}

export fn uacpi_kernel_pci_device_open(
    addr: uacpi.PciAddress,
    out_handle: **HardwareIo,
) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{addr});
    // for now just return a HardwareIo object.
    out_handle.* = HardwareIo.fromInternal(.{
        .pci = .{
            .bus = addr.bus,
            .device = addr.device,
            .function = addr.function,
            .segment = addr.segment,
        },
    }) catch return .out_of_memory;
    return .ok;
}

comptime {
    for (&.{ u8, u16, u32 }) |T| {
        const S = struct {
            pub fn ir(handle: *HardwareIo, offset: usize, ret: *T) callconv(cc) uacpi.uacpi_status {
                trace(@src(), .{ handle.device, offset });
                ret.* = handle.read(T, offset) catch return .internal_error;
                return .ok;
            }
            pub fn iw(handle: *HardwareIo, offset: usize, value: T) callconv(cc) uacpi.uacpi_status {
                trace(@src(), .{ handle.device, offset, value });
                handle.write(T, offset, value) catch return .internal_error;
                return .ok;
            }
            pub fn pr(address: *anyopaque, offset: usize, ret: *T) callconv(cc) uacpi.uacpi_status {
                _ = ret;
                trace(@src(), .{ address, offset });
                return .unimplemented;
            }
            pub fn pw(address: *anyopaque, offset: usize, value: T) callconv(cc) uacpi.uacpi_status {
                trace(@src(), .{ address, offset, value });
                return .unimplemented;
            }
        };

        @export(&S.ir, .{ .name = std.fmt.comptimePrint("uacpi_kernel_io_read{d}", .{@bitSizeOf(T)}) });
        @export(&S.iw, .{ .name = std.fmt.comptimePrint("uacpi_kernel_io_write{d}", .{@bitSizeOf(T)}) });
        @export(&S.pr, .{ .name = std.fmt.comptimePrint("uacpi_kernel_pci_read{d}", .{@bitSizeOf(T)}) });
        @export(&S.pw, .{ .name = std.fmt.comptimePrint("uacpi_kernel_pci_write{d}", .{@bitSizeOf(T)}) });
    }
}

export fn uacpi_kernel_pci_device_close(hwio: *HardwareIo) void {
    trace(@src(), .{hwio.device});
    hwio.header.unref();
}

export fn uacpi_kernel_io_map(base: u64, len: usize, out_hwio: **HardwareIo) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{ base, len });
    out_hwio.* = HardwareIo.fromInternal(.{
        .systemio = .{
            .base = base,
            .length = len,
        },
    }) catch return .out_of_memory;
    return .ok;
}

export fn uacpi_kernel_io_unmap(hwio: *HardwareIo) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{hwio.header});
    hwio.header.unref();
    return .ok;
}

// TODO: override arch helper so we no longer just an extra 32-bits.
pub const uacpi_thread_id = packed struct(u64) {
    id: Thread.Id,
    _: u32 = 0,
};

export fn uacpi_kernel_get_thread_id() callconv(cc) uacpi_thread_id {
    trace(@src(), .{});
    const currentThread = kpcb.current().scheduler.getCurrentThread() orelse return .{
        .id = .{ .uint = 0 },
    };
    return .{ .id = currentThread.id };
}

export fn uacpi_kernel_get_nanoseconds_since_boot() callconv(cc) u64 {
    trace(@src(), .{});
    // todo
    return 0;
}

export fn uacpi_kernel_stall(usec: u8) callconv(cc) void {
    // todo
    trace(@src(), .{usec});
}

export fn uacpi_kernel_sleep(msec: u64) callconv(cc) void {
    // todo
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
    return .ok;
}

export fn uacpi_kernel_uninstall_interrupt_handler(_: uacpi.InterruptHandler, _: *anyopaque) callconv(cc) uacpi.uacpi_status {
    trace(@src(), .{});
    return .ok;
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
    