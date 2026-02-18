const std = @import("std");
const uefi = std.os.uefi;

pub fn main() uefi.Error!void {
    const pr = try uefi.system_table.boot_services.?.locateProtocol(uefi.protocol.SimpleFileSystem, null);

    const vol = try pr.?.openVolume();

    const file = try vol.open("test.text", .read, .{});
    
    var buf: [5]u8 = .{0} ** 5;
    file.read(&buf[0..4]);

    
    
    // Prints to stderr, ignoring potential errors.
    try uefi.system_table.con_out.?.clearScreen();
}
