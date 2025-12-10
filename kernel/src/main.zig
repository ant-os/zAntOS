const std = @import("std");
const BOOTBOOT = @import("bootboot.zig").BOOTBOOT;

const fontEmbedded = @embedFile("font.psf");

// imported virtual addresses, see linker script
extern var bootboot: BOOTBOOT; // see bootboot.zig
extern var environment: [4096]u8; // configuration, UTF-8 text key=value pairs
extern var fb: u8; // linear framebuffer mapped

// Display text on screen
const PsfFont = packed struct {
    magic: u32, // magic bytes to identify PSF
    version: u32, // zero
    headersize: u32, // offset of bitmaps in file, 32
    flags: u32, // 0 if there's no unicode table
    numglyph: u32, // number of glyphs
    bytesperglyph: u32, // size of each glyph
    height: u32, // height in pixels
    width: u32, // width in pixels
};

// function to display a string
pub inline fn puts(comptime string: []const u8) void {
    @setRuntimeSafety(false);
    const font: PsfFont = @bitCast(fontEmbedded[0..@sizeOf(PsfFont)].*);
    const bytesperline = (font.width + 7) / 8;
    var framebuffer: [*]u32 = @ptrCast(@alignCast(&fb));
    for (string, 0..) |char, i| {
        var offs = i * (font.width + 1) * 4;
        var idx = if (char > 0 and char < font.numglyph) blk: {
            break :blk font.headersize + (char * font.bytesperglyph);
        } else blk: {
            break :blk font.headersize + (0 * font.bytesperglyph);
        };

        for (0..font.height) |_| {
            var line = offs;
            var mask = @as(u32, 1) << @as(u5, @intCast(font.width - 1));

            for (0..font.width) |_| {
                if ((fontEmbedded[idx] & mask) == 0) {
                    framebuffer[line / @sizeOf(u32)] = 0x000000;
                } else {
                    framebuffer[line / @sizeOf(u32)] = 0xFFFFFF;
                }
                mask >>= 1;
                line += 4;
            }

            framebuffer[line / @sizeOf(u32)] = 0;
            idx += bytesperline;
            offs += bootboot.fb_scanline;
        }
    }
}

fn inb(port: u16) u8 {
    return asm (
        \\ inb %al, %dx
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

fn outb(port: u16, value: u8) void {
    asm volatile (
        \\ outb %al, %dx
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

const DirectPortIO = struct {
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

    fn writer(self: *const @This()) Writer {
        return .{ .context = self.port };
    }
};

const NewDirectPortIO = struct {
    port: u16,

    // pub fn writer(port: u16) Writer {
    //     return .{ .port = port, .interface = std.Io.Writer{
    //         .buffer = &g_buffer,
    //         .vtable = &vtable,
    //     } };
    // }

    //const vtable = std.Io.Writer.VTable{ .drain = Writer.drain, .flush = std.io.Writer.noopFlush, .rebase = Writer.rebase };
    pub const Writer = struct {
        port: u16,
        interface: std.Io.Writer,

        fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
            const self: *Writer = @fieldParentPtr("interface", io_w);

            _ = splat;

            return try DirectPortIO.write(self.port, data[0]);
        }
    };
};

fn kmain() !void {
    const debugconp = DirectPortIO.new(0xe9);
    try debugconp.writer().print("BOOTBOOT = {any}\n", .{bootboot});

    for (bootboot.mmap_entries()) |entry| { // for some REASON the zig formatter love LONG lines...
        try debugconp.writer().print("0x{X}-0x{X} ({d} KiB, {d} 4Kib Pages) is of type {any}\n", .{ entry.getPtr(), entry.getPtr() + entry.getSizeInBytes(), entry.getSizeInBytes() / 1025, entry.getSizeIn4KiBPages(), entry.getType() });
    }
}

// Entry point, called by BOOTBOOT Loader
export fn _start() callconv(.c) noreturn {
    // NOTE: this code runs on all cores in parallel

    const s = bootboot.fb_scanline;
    const w = bootboot.fb_width;
    const h = bootboot.fb_height;
    var framebuffer: [*]u32 = @ptrCast(@alignCast(&fb));

    _ = kmain() catch {
        unreachable;
    };
    //  var debugcon = Port2.writer(0xe9);

    // var intf = &debugcon.interface;

    //_ = try intf.write("Simple Message");
    // _ = try intf.print("test", .{});*/
    if (s > 0) {
        // cross-hair to see screen dimension detected correctly
        for (0..h) |y| {
            framebuffer[(s * y + w * 2) / @sizeOf(u32)] = 0x00FFFFFF;
        }

        for (0..w) |x| {
            framebuffer[(s * (h / 2) + x * 4) / @sizeOf(u32)] = 0x00FFFFFF;
        }

        // red, green, blue boxes in order
        inline for (0..20) |y| {
            for (0..20) |x| {
                framebuffer[(s * (y + 20) + (x + 20) * 4) / @sizeOf(u32)] = 0x00FF0000;
            }
        }

        inline for (0..20) |y| {
            for (0..20) |x| {
                framebuffer[(s * (y + 20) + (x + 50) * 4) / @sizeOf(u32)] = 0x0000FF00;
            }
        }

        inline for (0..20) |y| {
            for (0..20) |x| {
                framebuffer[(s * (y + 20) + (x + 80) * 4) / @sizeOf(u32)] = 0x000000FF;
            }
        }

        // say hello
        puts("Welcome to zAntOS, the zig rewrite of AntOS (e.g. AntOS v3).");
    }

    // HALT IT ALL!!!!
    while (true) {}
}
