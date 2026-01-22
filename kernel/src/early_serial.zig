const io = @import("io.zig");
const std = @import("std");

const klog = std.log.scoped(.early_serial);

const CLOCK_FREQ = 115200;

pub const COM1: u16 = 0x3f8;

var read_buffer: [8]u8 = undefined;

pub const SerialPort = struct {
    const Self = @This();

    ioport: u16,
    reader: std.io.Reader,
    writer: std.io.Writer = .{
        .vtable = &std.io.Writer.VTable{
            .drain = drainWriter,
        },
        .buffer = &.{},
    },

    fn drainWriter(w: *std.io.Writer, data: []const []const u8, splat: usize) std.io.Writer.Error!usize {
        const self: *SerialPort = @fieldParentPtr("writer", w);

        // klog.debug("drainWriter() called on serial port {x} with data of {any} and splat of {d}", .{
        //     self.ioport,
        //     data,
        //     splat,
        // });

        var written: usize = 0;

        for (data, 0..) |slice, idx| {
            if (idx == data.len - 1) {
                for (0..splat) |_| {
                    self.writeBytes(slice);
                    written += slice.len;
                }
            } else {
                self.writeBytes(slice);
                written += slice.len;
            }
        }

        return written;
    }

    pub fn writeBytes(self: *SerialPort, data: []const u8) void {
        for (data) |byte| {
            self.writeByte(byte);
        }
    }

    fn streamFromReader(r: *std.io.Reader, w: *std.io.Writer, limit: std.io.Limit) std.io.Reader.StreamError!usize {
        const self: *SerialPort = @fieldParentPtr("reader", r);
        var new_limit = limit;
        var read: usize = 0;

        while (true) {
            new_limit = new_limit.subtract(1) orelse break;
            const c = self.readByte();
            try w.writeByte(c);

            std.log.debug("recv char: {x}", .{c});

            read += 1;
        }

        return read;
    }

    pub fn init(self: *const Self) !void {
        const port = self.ioport;
        io.outb(port + 1, 0x00);
        io.outb(port + 3, 0x80);
        io.outb(port + 0, 0x03);
        io.outb(port + 1, 0x00);
        io.outb(port + 3, 0x03);
        io.outb(port + 2, 0xC7);
        io.outb(port + 4, 0x0B);
        io.outb(port + 4, 0x1E);

        io.outb(port + 0, 0xAE);

        if (io.inb(port) != 0xAE) return error.FaultyDevice;

        // loop back test passed
        io.outb(port + 4, 0x0F);
    }

    pub inline fn new(port: u16) Self {
        return .{
            .ioport = port,
            .reader = .{
                .buffer = &.{},
                .end = 0,
                .vtable = &std.io.Reader.VTable{
                    .stream = streamFromReader,
                },
                .seek = 0,
            },
        };
    }

    pub fn readByte(self: *const SerialPort) u8 {
        while (!self.getLineStatus().data_ready) {}

        return io.inb(self.ioport);
    }

    pub fn writeByte(self: *const SerialPort, byte: u8) void {
        while (!self.getLineStatus().thre) {}

        io.outb(self.ioport, byte);
    }

    pub inline fn getLineStatus(self: *const SerialPort) LineStatus {
        return @bitCast(io.inb(self.ioport + 5));
    }

    const LineStatus = packed struct(u8) {
        data_ready: bool,
        overrun_error: bool,
        parity_error: bool,
        framing_error: bool,
        break_ind: bool,
        thre: bool,
        temt: bool,
        impending_error: bool,
    };
};
