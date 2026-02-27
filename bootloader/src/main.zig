const std = @import("std");
const toml = @import("toml");
const uefi = std.os.uefi;
const log = std.log.scoped(.antboot2);

const EfiFile = uefi.protocol.File;

var buffer: [0x1000]u8 = undefined;

pub const version_string = "2.0.0-indev";
const ParsedInstallConfig = toml.Parsed(InstallConfig);

const toWideStringComptime = std.unicode.utf8ToUtf16LeStringLiteral;
pub fn toWideString(buf: []const u8, alloc: std.mem.Allocator) ![*:0]const u16 {
    if (@inComptime()) return std.unicode.utf8ToUtf16LeStringLiteral(buf);
    return (try std.unicode.utf8ToUtf16LeAllocZ(alloc, buf)).ptr;
}

pub fn detectOsInstallOnFilesystem(fs: *uefi.protocol.SimpleFileSystem) !?ParsedInstallConfig {
    const root = try fs.openVolume();

    const configfile = root.open(
        comptime toWideString("\\AntOS\\config.toml", undefined) catch unreachable,
        .read,
        .{},
    ) catch |e| {
        if (e == error.NotFound) return null;
        return e;
    };
    defer configfile.close() catch {};

    const infoSize = try configfile.getInfoSize(.file);
    const infoBuf = try uefi.pool_allocator.alignedAlloc(
        u8,
        std.mem.Alignment.of(uefi.protocol.File.Info.File),
        infoSize,
    );
    defer uefi.pool_allocator.free(infoBuf);

    const fileInfo = try configfile.getInfo(.file, infoBuf);

    const fileContents = try uefi.pool_allocator.alloc(u8, fileInfo.file_size);
    defer uefi.pool_allocator.free(fileContents);

    _ = try configfile.read(fileContents);

    var parser = toml.Parser(InstallConfig).init(uefi.pool_allocator);
    defer parser.deinit();

    const config = try parser.parseString(fileContents);

    if (!std.mem.eql(u8, config.value.version, InstallConfig.VERSION)) return error.MismatchedVersion;
    if (!std.mem.eql(u8, config.value.loader.version, version_string)) return error.MismatchedLoaderVersion;

    return config;
}

const efiSystemrootPath = "\\AntOS";

pub fn convertPathToEfi(path: []const u8, alloc: std.mem.Allocator) ![*:0]const u16 {
    const fixed = try alloc.dupe(u8, path);
    defer alloc.free(fixed);

    std.mem.replaceScalar(u8, fixed, '/', '\\');
    const resolved = try std.mem.replaceOwned(
        u8,
        alloc,
        fixed,
        "$SYSTEMROOT$",
        efiSystemrootPath,
    );
    defer alloc.free(resolved);

    return toWideString(resolved, alloc);
}

pub const OsInstallation = struct {
    parsed_config: ParsedInstallConfig,
    systemroot: *EfiFile,

    fn alloc(self: *OsInstallation) std.mem.Allocator {
        return self.parsed_config.arena.allocator();
    }

    pub fn config(self: *const OsInstallation) *const InstallConfig {
        return &self.parsed_config.value;
    }

    pub fn open(self: *OsInstallation, path: []const u8, mode: EfiFile.OpenMode) !*EfiFile {
        if (mode == .read_write_create) return error.InvalidParameter;

        const realpath = try convertPathToEfi(path, self.alloc());
        defer self.alloc().free(realpath[0..std.mem.len(realpath)]);

        return self.systemroot.open(realpath, mode, .{});
    }
};

pub fn getFirstOsInstall() !OsInstallation {
    const filesystems = try efiBootServices().locateHandleBuffer(.{
        .by_protocol = &uefi.protocol.SimpleFileSystem.guid,
    }) orelse return error.NoFilesystemsFound;

    for (filesystems) |fs_handle| {
        const fs = try efiBootServices().openProtocol(
            uefi.protocol.SimpleFileSystem,
            fs_handle,
            .{ .by_handle_protocol = .{ .agent = uefi.handle } },
        ) orelse continue;
        const config = (detectOsInstallOnFilesystem(fs) catch |e| {
            try efiBootServices().closeProtocol(
                fs_handle,
                uefi.protocol.SimpleFileSystem,
                uefi.handle,
                null,
            );
            log.info("failed to detect install with error: {s}", .{@errorName(e)});
            continue;
        }) orelse {
            try efiBootServices().closeProtocol(
                fs_handle,
                uefi.protocol.SimpleFileSystem,
                uefi.handle,
                null,
            );

            continue;
        };
        const root = try fs.openVolume();

        return .{
            .parsed_config = config,
            .systemroot = try root.open(
                toWideStringComptime(efiSystemrootPath),
                .read,
                .{},
            ),
        };
    }

    return error.NotFound;
}

const InstallConfig = struct {
    pub const VERSION = "0.0.1-antinstall";

    version: []const u8,
    loader: struct {
        name: []const u8,
        version: []const u8,
        verbose: bool,
    },
    system: struct {
        osname: []const u8,
        version: []const u8,
    },
    kernel: struct {
        @"image-path": []const u8,
        parameters: toml.Table,
    },
};

pub fn _logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const chars = std.fmt.bufPrint(
        &buffer,
        "[{s}] {s}: " ++ format ++ "\r\n",
        .{ @tagName(level), @tagName(scope) } ++ args,
    ) catch @panic("buffer to small");

    for (chars) |c| {
        const wide = &[_]u16{ @intCast(c), 0, 0, 0 };
        _ = uefi.system_table.con_out.?.outputString(@ptrCast(wide)) catch unreachable;
    }
}

pub const std_options = std.Options{
    .logFn = _logFn,
    .fmt_max_depth = 3,
};

pub inline fn efiBootServices() *uefi.tables.BootServices {
    return uefi.system_table.boot_services.?;
}

const AntModuleDataMemory: uefi.tables.MemoryType = @enumFromInt(0xAA000001);

pub fn efiGetFileInfo(
    self: *uefi.protocol.File,
    comptime info: std.meta.Tag(uefi.protocol.File.Info),
    alloc: std.mem.Allocator,
) uefi.Error!struct { *@FieldType(uefi.protocol.File.Info, @tagName(info)), []u8 } {
    const size = try self.getInfoSize(info);
    const buf = alloc.alignedAlloc(
        u8,
        std.mem.Alignment.of(uefi.protocol.File.Info.File),
        size,
    ) catch return error.OutOfResources;
    return .{ try self.getInfo(info, buf), buf };
}

pub inline fn errorCast(comptime E: type, err: anytype) ?E {
    switch (err) {
        inline else => |e| comptime for (std.meta.fields(E)) |possibleError| {
            if (std.mem.eql(u8, possibleError.name, @errorName(e))) return @field(
                E,
                possibleError.name,
            );
        },
    }

    return null;
}

// 0x0000_0000_0000_0000..0x0000_0000_0100_0000: null
// 0x0000_0000_0100_0000..0x0000_7FFF_FFFF_0000: user mode
// 0x0000_7FFF_FFFF_0000..0x0000_8000_0000_0000: no access
//
// 0x0000_8000_0000_0000..0xFFFF_8000_0000_0000: not canonical
//
// 0xFFFF_8000_0000_0000..0xFFFF_B000_0000_0000: non-paged space pool
// 0xFFFF_B000_0000_0000..0xFFFF_F000_0000_0000: paged space pool
// load kernel and module files to (0xFFFF_F000_0000_0000..0xFFFF_F010_0000_0000)
// (0xFFFF_F010_0000_0000..0xFFFF_F800_0000_0000 is for loaded driver images)
// 0xFFFF_FA80_0000_0000..0xFFFF_FB80_0000_0000: Generic Memory Pool (PFMDB, Object Pools[Slab])
// 0xFFFF_FB80_0000_0000..0xFFFF_FC00_0000_0000: rescusive page tables
// 0xFFFF_FC00_0000_0000..0xFFFF_FC80_0000_0000: System PTE pool (for mmio)
// 0xFFFF_FC80_0000_0000..0xFFFF_FCFF_C000_0000: kernel stacks
// 0xFFFF_FCFF_C000_0000..0xFFFF_FD00_0000_0000: per-core data
// 0xFFFF_FD00_0000_0000..0xFFFF_FF00_0000_0000: framebuffers
// 0xFFFF_FFFF_8000_0000..0xFFFF_FFFF_FFFF_F000: kernel image

const PAGE_ALIGN = std.mem.Alignment.fromByteUnits(0x1000);

pub fn loadModuleData(install: *OsInstallation, path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    log.debug("loading {s}...", .{path});

    const file = try install.open(path, .read);
    defer file._close(file).err() catch |e| {
        log.err("failed to close file {s}: {s}", .{ path, @errorName(e) });
    };

    const fileInfo: *EfiFile.Info.File, const infoBuf = try efiGetFileInfo(file, .file, alloc);
    defer alloc.free(infoBuf);

    const raw: []u8 = @ptrCast(try efiBootServices().allocatePages(
        .any,
        AntModuleDataMemory,
        PAGE_ALIGN.forward(fileInfo.file_size) / 0x1000,
    ));

    const read = try file.read(raw[0..fileInfo.file_size]);

    return raw[0..read];
}

pub const PTE = packed struct {
    present: bool,
    writable: bool,
    user: bool,
    write_through: bool,
    disable_cache: bool,
    accessed: bool,
    dirty: bool = false,
    pat: bool = false,
    huge: bool = false,
    avail0: u3,
    addr: u40,
    avail1: u11,
    no_execute: bool,

    pub fn asTable(self: *const @This()) *[512]PTE {
        return @ptrFromInt(self.getAddr());
    }

    pub fn getAddr(self: *const @This()) u64 {
        return self.addr << 12;
    }

    pub fn setAddr(self: *@This(), addr: u64) void {
        self.addr = @intCast(addr >> 12);
    }
};

var pml4: ?*[512]PTE = null;

pub fn main() uefi.Error!void {
    const info = try uefi.system_table.boot_services.?.getMemoryMapInfo();
    std.log.info("info = {any}", .{info});
    var arena: std.heap.ArenaAllocator = .init(uefi.pool_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    var install = getFirstOsInstall() catch |e| {
        log.err("failed to discover os installation: {s}", .{@errorName(e)});
        return errorCast(uefi.Error, e) orelse error.NoMedia;
    };

    const volumeLabel = blk: {
        const label, const buf = try efiGetFileInfo(install.systemroot, .volume_label, alloc);
        defer alloc.free(buf);
        const raw = label.getVolumeLabel();

        break :blk std.unicode.utf16LeToUtf8Alloc(
            alloc,
            raw[0..std.mem.len(raw)],
        ) catch {
            log.err("non-utf8 volume label", .{});
            return uefi.Error.VolumeCorrupted;
        };
    };
    defer alloc.free(volumeLabel);
    log.info("Starting {s} (version {s}) from \"{s}\"", .{
        install.config().system.osname,
        install.config().system.version,
        volumeLabel,
    });

    const kernelImage = loadModuleData(&install, install.config().kernel.@"image-path", alloc) catch |e| {
        log.err("failed to load kernel image: {s}", .{@errorName(e)});
        return errorCast(uefi.Error, e) orelse error.LoadError;
    };
    // no free becuse image will stay loaded past kernel handoff.

    log.info("kernel image data loaded at 0x{x} with size of {d}", .{
        @intFromPtr(kernelImage.ptr),
        kernelImage.len,
    });

    const elfHdr = std.elf.Header.init(
        @as(*const std.elf.Ehdr, @ptrCast(@alignCast(kernelImage.ptr))).*,
        .little,
    );

    log.info("kernel elf header: {any}", .{elfHdr});

    var phdrIter = elfHdr.iterateProgramHeadersBuffer(kernelImage);

    while (phdrIter.next() catch |e|{
        log.err("failed to load kernel image: {s}", .{@errorName(e)});
        return errorCast(uefi.Error, e) orelse error.LoadError;
    }) |e| {
        log.info("program header: {any}", .{e});
    }

    // const mem = uefi.pool_allocator.alignedAlloc(
    //     u8,
    //     .@"8",
    //     (info.len + 1) * info.descriptor_size,
    // ) catch unreachable;

    // const mmap = try uefi.system_table.boot_services.?.getMemoryMap(
    //     mem,
    // );

    //   var mmapiter = mmap.iterator();

    // while (mmapiter.next()) |md| std.log.debug("{any}", .{md});

    // const sfs = (try efiBootServices().locateDevicePath(
    //     uefi.protocol.SimpleFileSystem,
    //     uefizzz
    //     .{},
    // )) orelse {
    //     log.err("unable to locate simple filesystem protocol", .{});
    //     return uefi.Status.not_found;
    // };
    // efiBootServices().closeProtocol(efiBootServices()

    // log.debug("filesystem = {any}", .{sfs});

    // const root = try sfs.openVolume();

    // log.debug("filesystem = {any}", .{sfs});

    while (true) {
        asm volatile ("hlt");
    }
}
