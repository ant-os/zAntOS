const std = @import("std");
const bootboot = @import("bootboot.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const pageFrameAllocator = @import("pageFrameAllocator.zig");
const klog = std.log.scoped(.kernel);
const paging = @import("paging.zig");
const heap = @import("heap.zig");
const antstatus = @import("status.zig");
const ANTSTATUS = antstatus.Status;

const fontEmbedded = @embedFile("font.psf");
const QEMU_DEBUGCON = 0xe9;

pub const std_options: std.Options = .{ .log_level = .debug, .logFn = kernelLog };
pub fn kernelLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    io.DirectPortIO.new(0xe9).writer().print(std.fmt.comptimePrint("[{s}] {s}: {s}\n", .{
        @tagName(message_level),
        @tagName(scope),
        format,
    }), args) catch {
        io.DirectPortIO.writeString(0xe9, "[<log internal error>] format = ");
        io.DirectPortIO.writeString(0xe9, format);
        io.outb(0xe9, '\n');
        // std.io.Writer.print(w: *Writer, comptime fmt: []const u8, args: anytype)
    };
}

pub noinline fn kmain() !void {
    klog.info("Starting zAntOS...", .{});

    klog.info("Total physical memory of {d} KiB", .{memory.KePhysicalMemorySize() / 1024});

    pageFrameAllocator.init() catch |e| {
        klog.err("Failed to initalize page bitmap: {s}", .{@errorName(e)});
        return;
    };

    const myPage = try pageFrameAllocator.requestPage();

    klog.debug("my page: {d} ({x})", .{ myPage, myPage * 0x1000 });

    klog.debug("Allocated Page: {x}", .{(try pageFrameAllocator.requestPage()) * 0x1000});

    klog.info("Used Memory: {d}/{d} KiB", .{
        pageFrameAllocator.getUsedMemory() / 1024,
        memory.KePhysicalMemorySize() / 1024,
    });

    klog.info("Free Memory: {d}/{d} KiB", .{
        pageFrameAllocator.getFreeMemory() / 1024,
        memory.KePhysicalMemorySize() / 1024,
    });

    paging.init() catch |e| {
        klog.err("Failed to initalize kernel paging: {s}", .{@errorName(e)});
        return;
    };

    heap.init(1) catch |e| {
        klog.err("Failed to initalize kernel heap: {s}", .{@errorName(e)});
        return;
    };

    klog.info("Parsing initrd...", .{});

    const initrd: [*]align(1) u8 = @ptrFromInt(bootboot.bootboot.initrd_ptr);
    var initrd_reader = std.io.Reader.fixed(initrd[0..bootboot.bootboot.initrd_size]);
    var tar_iter = std.tar.Iterator.init(&initrd_reader, .{
        .file_name_buffer = try heap.allocator.alloc(u8, 255),
        .link_name_buffer = try heap.allocator.alloc(u8, 255),
    });

    var file: std.tar.Iterator.File = undefined;
    for (0..2) |_| {
        file = (try tar_iter.next()) orelse break;
        if (std.ascii.endsWithIgnoreCase(file.name, ".text")) {
            klog.info("file {s} ({d} bytes): {s}", .{
                file.name,
                file.size,
                try initrd_reader.readAlloc(heap.allocator, file.size),
            });
        } else {
            klog.info("file {s} ({d} bytes): <not a text file>", .{
                file.name,
                file.size,
            });
        }

        if (initrd_reader.seek == bootboot.bootboot.initrd_size - 1) break;
    }

    heap.dumpSegments();

    var status = ANTSTATUS.err(.invalid_alignement);

    klog.debug("status: {f}", .{status});
    klog.debug("zig error: {any}", .{status.intoZigError()});
    klog.debug("c-style error code: 0x{x}.", .{status.asU64()});
    klog.debug("casted from int of 0x70..3: {f}", .{ANTSTATUS.fromU64(0x7000000000000003)});

    klog.info("Reached end of kmain()", .{});
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
    if (bootboot.bootboot.numcores > 1)
        klog.err("More than one CPU cores are currently not supported", .{});

    // NOTE: this code runs on all cores in parallel

    // const s = bootboot.fb_scanline;
    // const w = bootboot.fb_width;
    // const h = bootboot.fb_height;
    // var framebuffer: [*]u32 = @ptrCast(@alignCast(&fb));

    _ = kmain() catch |e| {
        klog.err("\n\nkmain() failed with error: {any}\n", .{e});
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
