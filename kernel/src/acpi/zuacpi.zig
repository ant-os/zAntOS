// zuacpi binding

const bootloader = @import("../bootloader.zig");
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


pub fn get_rsdp() u64 {
    return @intFromPtr(bootloader.info.acpi_ptr orelse @panic("acpi not supported"));
}
