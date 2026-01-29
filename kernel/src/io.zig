const std = @import("std");

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
