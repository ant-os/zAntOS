//! AntOS Operating System Kernel Main File

// AntOS Kernel

const antos_kernel = @import("root");

const std = @import("std");
const bootboot = @import("bootboot.zig");
const io = @import("io.zig");
const memory = @import("memory.zig");
const pageFrameAllocator = @import("pageFrameAllocator.zig");
const klog = std.log.scoped(.kernel);
const paging = @import("paging.zig");
const heap = @import("heap.zig");
const antstatus = @import("status.zig");
pub const ANTSTATUS = antstatus.ANTSTATUS;
const filesystem = @import("filesystem.zig");
const driverManager = @import("driverManager.zig");
const driverCallbacks = @import("driverCallbacks.zig");
const builtindrv_initrdfs = @import("initrdfs.zig");
const ramdisk = @import("ramdisk.zig");
const resource = @import("resource.zig");
const early_serial = @import("early_serial.zig");
const shell = @import("shell/shell.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");

pub const Executable = @import("executable.zig");
pub const BlockDevice = @import("blockdev.zig");

const fontEmbedded = @embedFile("font.psf");
const QEMU_DEBUGCON = 0xe9;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = kernelLog,
    .fmt_max_depth = 4,
};

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

var serial = early_serial.SerialPort.new(early_serial.COM1);
var allocating_wr = std.io.Writer.Allocating.init(heap.allocator);

pub noinline fn kmain() !void {
    defer heap.dumpSegments();

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

    var status = ANTSTATUS.err(.invalid_parameter);

    klog.debug("status: {f}", .{status});
    klog.debug("zig error: {any}", .{status.intoZigError()});
    klog.debug("c-style error code: 0x{x}.", .{status.asU64()});
    klog.debug("casted from int of 0x70..3: {f}", .{ANTSTATUS.fromU64(0x7000000000000003)});

    klog.info("kernel exe: {any}", .{Executable.kernel()});

    klog.debug("handle: {any}", .{resource.keAllocateHandle(.directory)});
    heap.dumpSegments();

    try serial.init();

    klog.debug("created com1 connection", .{});

    klog.debug("int called", .{});

    asm volatile ("sti");

    //var rd = &serial.reade, , )

    try shell.run(&serial.writer, &serial.reader);

    // var desc = try driverManager.register("ramdisk", .block, ramdisk.init, null, 0);
    // try desc.init();

    // const dhandle = try resource.create(null, .driver, @ptrCast(desc));

    // const params = try driverManager.SimpleKVPairs.construct(.{
    //     .base = bootboot.bootboot.initrd_ptr,
    //     .sizer = bootboot.bootboot.initrd_size,
    // });

    // klog.debug("Goal: Attach block device using driver 'ramdisk' and parameters {f}", .{params});

    // const rdblk: BlockDevice = try BlockDevice.attach(dhandle, params, null);

    // klog.debug("success!, BlockDevice instance: {any}", .{rdblk});

    // klog.debug("Goal: Map the first sector using BLOCK_MAP and print out the first bytes as a string until NULL", .{});

    // const bytes: [*:0]u8 = @ptrCast(try rdblk.mapSectors(0, 1, null));

    // klog.debug("success!, mapped to address {any} and read \"{s}\"", .{ bytes, bytes });

    // klog.debug("Goal: Repeat the string read from last goal at offset of 257", .{});
    // klog.debug("success!, read \"{s}\"", .{bytes[257..]});

    // // const initrdfs_drv = try builtindrv_initrdfs.install();
    // const mynote = try filesystem.open(initrdfs_drv, "note.text");
    // const fileinfo = try filesystem.getfileinfo(initrdfs_drv, mynote);
    // defer heap.allocator.destroy(fileinfo); // new as it no longer returns-by-value.

    // klog.debug("{any}", .{fileinfo});

    // const buf = try heap.allocator.alloc(u8, fileinfo.size);
    // defer heap.allocator.free(buf);

    // try filesystem.read(initrdfs_drv, mynote, buf);

    // klog.debug("my note: {s}", .{buf});

    // try filesystem.close(initrdfs_drv, mynote);

    klog.info("Reached end of kmain()", .{});
}

fn mydrv_init(o: *driverManager.DriverObject) callconv(.c) ANTSTATUS {
    klog.debug("driver: name = {s}", .{o.name});

    var first_param = o.paramter_values.?[0];

    klog.info("first param = {s}", .{first_param.getName()});

    return .SUCCESS;
}

pub fn panic(msg: []const u8, trace: anytype, addr: ?usize) noreturn {
    _ = trace;

    _ = io.DirectPortIO.writeString(0xe9, msg);
    _ = io.DirectPortIO.writeString(0xe9, "\n^ PANIC IN EARLY KERNEL CODE\n");

    if (serial.initalized) {
        serial.writeBytes("\n\r==== KERNEL PANIC ====\n\r");
        serial.writeBytes("* Status: <zig panic>\n\r");
        serial.writeBytes("* Message: ");
        serial.writeBytes(msg);
        serial.writeBytes("\n\r* Panicked at 0x");
        if (addr) |a| serial.writeBytes(&std.fmt.hex(a)) else serial.writeBytes("<unkown>");
        serial.writeBytes("\n\r* Panic Type: ZIG_LANG_PANIC");
    }
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

    gdt.init();
    idt.init();

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
