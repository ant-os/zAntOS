const std = @import("std");

const LOADER_BLOCK = opaque {};
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
const BootInfo = extern struct {
    const Memory = extern struct {
        descriptors: [*]const u8,
        descriptor_size: usize,
        descriptor_count: usize,
    };

    const Image = extern struct {
        path: [*:0]const u8,
        base: usize,
        size: usize,
    };

    major_verion: usize = 1,
    minor_verion: usize = 0,
    size: usize,

    kernel_image: Image,
    memory: Memory,
};

export fn antkStartupSystem(info: *BootInfo) callconv(cc) noreturn {
    const io = DirectPortIO.new(0x3f8);
    io.writer().print("Hello, World!\r\n", .{}) catch unreachable;
    io.writer().print("Boot Info: {any}\r\n", .{info}) catch unreachable;

    while (true) {
        asm volatile ("hlt");
    }
}
