const std = @import("std");
const antboot = @import("bootloader");

const cc = std.builtin.CallingConvention{ .x86_64_sysv = .{} };

pub inline fn inb(port: u16) u8 {
    return asm (
        \\ inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

pub inline fn outb(port: u16, value: u8) void {
    asm volatile (
        \\ outb %[value], %[port]
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

pub const DirectPortIO = struct {
    port: u16,

    pub fn new(port: u16) DirectPortIO {
        return .{ .port = port };
    }

    const Writer = std.io.GenericWriter(u16, error{}, write);

    pub fn write(port: u16, data: []const u8) !usize {
        for (data) |byte| {
            outb(port, byte);
        }

        return data.len;
    }

    pub fn writeString(port: u16, data: []const u8) usize {
        for (data) |byte| {
            outb(port, byte);
        }

        return data.len;
    }

    pub fn writer(self: *const @This()) Writer {
        return .{ .context = self.port };
    }
};

export fn antkStartupSystem(info: *antboot.BootInfo) callconv(cc) noreturn {
    const io = DirectPortIO.new(0x3f8);
    io.writer().print("Hello from the test kernel!\r\n", .{}) catch unreachable;
    io.writer().print("Boot Info: {any}\r\n", .{info}) catch unreachable;

    var buf: [256]u8 align(2) = .{0} ** 256;

    const vendor = info.efi_ptr.firmware_vendor;

    const end = std.unicode.utf16LeToUtf8(&buf, vendor[0..std.mem.len(vendor)]) catch 0;

    io.writer().print("efi vendor: {s}\n", .{buf[0..end]}) catch {};

    while (true) {
        asm volatile ("hlt");
    }
}
