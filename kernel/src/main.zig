const std = @import("std");
const bootboot = @import("bootboot.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const pageFrameAllocator = @import("pageFrameAllocator.zig");

const fontEmbedded = @embedFile("font.psf");

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

pub noinline fn kmain() !void {
    const debugconp = io.DirectPortIO.new(0xe9);
    const writer = debugconp.writer();

    // _ = try writer.write("This written using .write().\n");
    try std.fmt.format(writer, "stuff BOOTBOOT tells us: {any}\n", .{bootboot.bootboot});

    try debugconp.writer().print("Total: {d}GiB\n", .{memory.KePhysicalMemorySize() / 1024 / 1024 / 1024});

    try pageFrameAllocator.init();

    const myPage = try pageFrameAllocator.requestPage();

    try debugconp.writer().print("\nmy page: {d} ({x})\n", .{ myPage, myPage * 0x1000 });

    try debugconp.writer().print("Allocated Page: {x}\n", .{(try pageFrameAllocator.requestPage()) * 0x1000});

    try debugconp.writer().print("Used Memory: {d}/{d} KiB\n", .{
        pageFrameAllocator.getUsedMemory() / 1024,
        memory.KePhysicalMemorySize() / 1024,
    });

    try debugconp.writer().print("Free Memory: {d}/{d} KiB\n", .{
        pageFrameAllocator.getFreeMemory() / 1024,
        memory.KePhysicalMemorySize() / 1024,
    });

    while (true) {
        const c = io.inb(0xe9);

        if (std.ascii.isAlphabetic(c))
            io.outb(0xe9, c);
    }
}

pub fn panic(msg: []const u8, trace: anytype, addr: ?usize) noreturn {
    _ = trace;
    _ = addr;

    _ = io.DirectPortIO.writeString(0xe9, msg);
    _ = io.DirectPortIO.writeString(0xe9, "\n^ PANIC IN EARLY KERNEL CODE\n");
    while (true) {
        asm volatile ("hlt");
    }
}

// Entry point, called by BOOTBOOT Loader
export fn _start() callconv(.c) noreturn {
    // NOTE: this code runs on all cores in parallel

    // const s = bootboot.fb_scanline;
    // const w = bootboot.fb_width;
    // const h = bootboot.fb_height;
    // var framebuffer: [*]u32 = @ptrCast(@alignCast(&fb));

    io.outb(0xe9, '.');

    _ = kmain() catch |e| {
        io.DirectPortIO.new(0xe9).writer().print("\n\nkmain() failed with error: {any}\n", .{e}) catch {
            @panic("kmain() returned an error.");
        };

        while (true) {
            asm volatile ("hlt");
        }
    };
    //  var debugcon = Port2.writer(0xe9);

    // var intf = &debugcon.interface;

    //_ = try intf.write("Simple Message");
    // _ = try intf.print("test", .{});*/
    // if (s > 0) {
    //     // cross-hair to see screen dimension detected correctly
    //     for (0..h) |y| {
    //         framebuffer[(s * y + w * 2) / @sizeOf(u32)] = 0x00FFFFFF;
    //     }

    //     for (0..w) |x| {
    //         framebuffer[(s * (h / 2) + x * 4) / @sizeOf(u32)] = 0x00FFFFFF;
    //     }

    //     // red, green, blue boxes in order
    //     inline for (0..20) |y| {
    //         for (0..20) |x| {
    //             framebuffer[(s * (y + 20) + (x + 20) * 4) / @sizeOf(u32)] = 0x00FF0000;
    //         }
    //     }

    //     inline for (0..20) |y| {
    //         for (0..20) |x| {
    //             framebuffer[(s * (y + 20) + (x + 50) * 4) / @sizeOf(u32)] = 0x0000FF00;
    //         }
    //     }

    //     inline for (0..20) |y| {
    //         for (0..20) |x| {
    //             framebuffer[(s * (y + 20) + (x + 80) * 4) / @sizeOf(u32)] = 0x000000FF;
    //         }
    //     }

    //     // say hello
    //     puts("Welcome to zAntOS, the zig rewrite of AntOS (e.g. AntOS v3).");
    // }*/

    // HALT IT ALL!!!!
    while (true) {
        asm volatile ("hlt");
    }
}
