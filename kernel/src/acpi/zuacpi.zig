// zuacpi binding

const bootboot = @import("../bootboot.zig");
const paging = @import("../mm/paging.zig");
const zuacpi = @import("zuacpi");

const RSDP = extern struct {
    signature: [8]u8,
    checksum: u8,
    oemid: [6]u8,
    revision: u8,
    rsdt: u32,
    length: u32,
    xsdt: u64,
    ext_checksum: u8,
    reserved: [3]u8,
};

export var __fake_rsdp: RSDP = .{
    .signature = "RSD PTR ".*,
    .oemid = "FAKE  ".*,
    .length = @sizeOf(RSDP),

    // ignore for now
    .checksum = 0,
    .ext_checksum = 0,
    

    // later set in fixup_acpi_ptr().
    .revision = 0,
    .rsdt = 0,
    .xsdt = 0,
    .reserved = [_]u8{0,0,0},
};

pub fn get_rsdp() u64 {
    fixup_acpi_ptr();
    return paging.translateAddr(@intFromPtr(&__fake_rsdp)) catch unreachable;
}

var has_fixed_rsdp: bool = false;

/// fixup the bootboot acpi pointer to get a proper RSDP.
pub fn fixup_acpi_ptr() void {
    if (has_fixed_rsdp) return;

    // assuming iddenty mapping of low ram when first called.

    const acpi: *zuacpi.sdt.SystemDescriptorTableHeader = @ptrFromInt(bootboot.bootboot.arch.x86_64.acpi_ptr);

    switch (acpi.signature) {
        // verion 1
        .RSDT => {
            __fake_rsdp.revision = 1;
            __fake_rsdp.rsdt = @intCast(@intFromPtr(acpi));
        },
        // verion 2
        .XSDT => {
            __fake_rsdp.revision = 2;
            __fake_rsdp.xsdt = @intCast(@intFromPtr(acpi));
        },
        else => @panic("invalid acpi table pointer")
    }

    has_fixed_rsdp = true;
}

const std = @import("std");
comptime {
    _ = std.mem.doNotOptimizeAway(@import("shims.zig"));
}
