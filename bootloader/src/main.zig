const std = @import("std");
const toml = @import("toml");
const uefi = std.os.uefi;
const log = std.log.scoped(.antboot2);

const EfiFile = uefi.protocol.File;

var logBuffer: [8 * 0x1000]u8 = undefined;

pub const version_string = "2.0.0-indev";
const ParsedBootConfig = toml.Parsed(BootConfig);

const toWideStringComptime = std.unicode.utf8ToUtf16LeStringLiteral;
pub fn toWideString(buf: []const u8, alloc: std.mem.Allocator) ![*:0]const u16 {
    if (@inComptime()) return std.unicode.utf8ToUtf16LeStringLiteral(buf);
    return (try std.unicode.utf8ToUtf16LeAllocZ(alloc, buf)).ptr;
}

pub fn detectOsInstallOnFilesystem(fs: *uefi.protocol.SimpleFileSystem) !?ParsedBootConfig {
    const root = try fs.openVolume();

    const configfile = root.open(
        comptime toWideString("\\AntOS\\boot.toml", undefined) catch unreachable,
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

    var parser = toml.Parser(BootConfig).init(uefi.pool_allocator);
    defer parser.deinit();

    const config = try parser.parseString(fileContents);

    if (!std.mem.eql(u8, config.value.version, BootConfig.VERSION)) return error.MismatchedVersion;
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
    parsed_config: ParsedBootConfig,
    systemroot: *EfiFile,

    fn alloc(self: *OsInstallation) std.mem.Allocator {
        return self.parsed_config.arena.allocator();
    }

    pub fn config(self: *const OsInstallation) *const BootConfig {
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

const BootConfig = @import("InstallConfig.zig");

pub fn _logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const chars = std.fmt.bufPrint(
        &logBuffer,
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

const AntGenericArenaMemory: uefi.tables.MemoryType = @enumFromInt(0xAA000000);
const AntModuleDataMemory: uefi.tables.MemoryType = @enumFromInt(0xAA000001);
const AntLoadedKernelMemory: uefi.tables.MemoryType = @enumFromInt(0xAA000002);
const AntEarlyReclaimableMemory: uefi.tables.MemoryType = @enumFromInt(0xAA000003);
const AntPreallocatedStackMemory: uefi.tables.MemoryType = @enumFromInt(0xAA000003);
// ...

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
// 0xFFFF_FA80_0000_0000..0xFFFF_FB80_0000_0000: Generic Memory Pool (Loader Mappings[later relcaimed], PFMDB, Genric Fixed-SLot Pool Area)
// 0xFFFF_FB80_0000_0000..0xFFFF_FC00_0000_0000: rescusive page tables
// 0xFFFF_FC00_0000_0000..0xFFFF_FC80_0000_0000: System PTE pool (for mmio)
// 0xFFFF_FC80_0000_0000..0xFFFF_FCFF_C000_0000: kernel stacks
// 0xFFFF_FCFF_C000_0000..0xFFFF_FD00_0000_0000: per-core data
// 0xFFFF_FD00_0000_0000..0xFFFF_FF00_0000_0000: framebuffers
// 0xFFFF_FFFF_8000_0000..0xFFFF_FFFF_FFFF_0000: kernel image
// 0xFFFF_FFFF_FFFF_1000..0xFFFF_FFFF_FFFF_8000: bsp-init stack.

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

pub const PageAttributes = packed struct(u8) {
    writable: bool = true,
    no_cache: bool = false,
    write_through: bool = false,
    user: bool = false,
    no_execute: bool = false,
    reserved: u3 = 0,
};

var pml4: ?*[512]PTE = null;

pub fn allocPageTable() !*[512]PTE {
    const pages = try efiBootServices().allocatePages(.any, .loader_data, 1);
    @memset(&pages[0], 0);
    return @ptrCast(&pages[0]);
}
pub const VirtualAddress = packed struct {
    pageoff: u12,
    pt: u9,
    pd: u9,
    pdp: u9,
    pml4: u9,
    signext: u16,

    pub fn raw(self: VirtualAddress) u64 {
        return @bitCast(self);
    }
};

pub fn allocatePages(pages: usize, ty: uefi.tables.MemoryType) ![]u8 {
    return @ptrCast(
        try efiBootServices().allocatePages(
            .{ .max_address = @ptrFromInt(@"16GiB") },
            ty,
            pages,
        ),
    );
}

pub fn installMapping(virtual: VirtualAddress, physical: u64, attrs: PageAttributes) !void {
    log.debug("TRACE: installMapping(vaddr = 0x{x}, paddr = 0x{x}, attrs = {any})", .{
        virtual.raw(),
        physical,
        attrs,
    });

    if (pml4 == null) pml4 = try allocPageTable();

    const pdp = try pml4.?[virtual.pml4].getOrCreateTable();
    const pd = try pdp[virtual.pdp].getOrCreateTable();
    const pt = try pd[virtual.pd].getOrCreateTable();
    const pte = &pt[virtual.pt];

    pte.setAddr(physical);
    pte.present = true;
    pte.writable = attrs.writable;
    pte.disable_cache = attrs.no_cache;
    pte.write_through = attrs.write_through;
    pte.user = attrs.user;
    pte.no_execute = attrs.no_execute;
}

const MappingSize = enum { @"1G", @"2M", @"4K" };
pub fn installMappingWithSize(virtual: VirtualAddress, physical: u64, attrs: PageAttributes, size: MappingSize) !void {

    if (pml4 == null) pml4 = try allocPageTable();

    const pdp = try pml4.?[virtual.pml4].getOrCreateTable();
    if (size == .@"1G") return installMappingAtEntry(&pdp[virtual.pdp], physical, attrs, size);
    const pd = try pdp[virtual.pdp].getOrCreateTable();
    if (size == .@"2M") return installMappingAtEntry(&pd[virtual.pd], physical, attrs, size);
    const pt = try pd[virtual.pd].getOrCreateTable();
    if (size == .@"4K") return installMappingAtEntry(&pt[virtual.pt], physical, attrs, size);

    @panic("unknown size");
}

inline fn installMappingAtEntry(pte: *PTE, physical: u64, attrs: PageAttributes, size: MappingSize) void {
    pte.setAddr(physical);
    pte.present = true;
    pte.huge = size != .@"4K";
    pte.writable = attrs.writable;
    pte.disable_cache = attrs.no_cache;
    pte.write_through = attrs.write_through;
    pte.user = attrs.user;
    pte.no_execute = attrs.no_execute;
}

pub const PTE = packed struct {
    present: bool,
    writable: bool,
    user: bool,
    write_through: bool,
    disable_cache: bool,
    accessed: bool,
    dirty: bool = false,
    huge: bool = false,
    pat: bool = false,
    avail0: u3,
    addr: u40,
    avail1: u11,
    no_execute: bool,

    pub fn getOrCreateTable(self: *PTE) !*[512]PTE {
        return if (self.present) @ptrFromInt(self.getAddr()) else blk: {
            const table = try allocPageTable();
            self.setAddr(@intFromPtr(table));
            self.present = true;
            self.writable = true;
            break :blk table;
        };
    }

    pub fn getAddr(self: *const @This()) u64 {
        return self.addr << 12;
    }

    pub fn setAddr(self: *@This(), addr: u64) void {
        self.addr = @intCast(addr >> 12);
    }
};

inline fn section_header(header: *const std.elf.Header, buffer: []const u8, index: u32) ?*const std.elf.Shdr {
    if (index > header.shnum) return null;
    const offset = header.shoff + @sizeOf(std.elf.Shdr) * index;
    return @ptrCast(@alignCast(&buffer[offset]));
}

inline fn section_name(header: *const std.elf.Header, buffer: []const u8, index: u32) ?[]const u8 {
    if (index == 0) return null;
    const shstr = section_header(
        header,
        buffer,
        header.shstrndx,
    ).?;

    return strtab_get(buffer, shstr, index);
}

inline fn strtab_get(buffer: []const u8, tab: *const std.elf.Shdr, index: u32) ?[]const u8 {
    if (index == 0) return null;

    if (index >= tab.sh_size) return null;

    const name: [*c]const u8 = buffer[tab.sh_offset + index ..].ptr;

    return name[0..std.mem.len(name)];
}

pub fn getHighestConvtionalPhysicalPage(alloc: std.mem.Allocator) !u64 {
    const info = try efiBootServices().getMemoryMapInfo();
    const buffer = alloc.alignedAlloc(
        u8,
        .of(uefi.tables.MemoryDescriptor),
        (info.len + 1) * info.descriptor_size,
    ) catch return error.OutOfResource;
    defer alloc.free(buffer);
    const mmap = try efiBootServices().getMemoryMap(buffer);
    var iter = mmap.iterator();

    var addr = 0;
    while (iter.next()) |desc| {
        const end = desc.physical_start + (desc.number_of_pages * 0x1000);
        if (end > addr) addr = end;
    }

    return addr / 0x1000;
}

const Gib = (1024 * 1024 * 1024);
const Mib = (1024 * 1024);
const @"16GiB" = 16 * Gib;

pub fn main() uefi.Error!void {
    asm volatile ("cli");
    var arena: std.heap.ArenaAllocator = .init(uefi.pool_allocator);
    const alloc = arena.allocator();

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

    log.debug("kernel image data loaded at 0x{x} with size of {d}", .{
        @intFromPtr(kernelImage.ptr),
        kernelImage.len,
    });

    log.info("parsing and loading kernel image...", .{});

    const elfHdr = std.elf.Header.init(
        @as(*const std.elf.Ehdr, @ptrCast(@alignCast(kernelImage.ptr))).*,
        .little,
    );

    //const loadedImage = try efiBootServices().handleProtocol(uefi.protocol.LoadedImage, uefi.handle);

   // log.info("{any}", .{loadedImage});

    log.info("kernel elf header: {any}", .{elfHdr});

    var shdrIter = elfHdr.iterateSectionHeadersBuffer(kernelImage);

    while (shdrIter.next() catch |e| {
        log.err("failed to parse section header: {s}", .{@errorName(e)});
        return errorCast(uefi.Error, e) orelse error.LoadError;
    }) |shdr| {
        log.info("section {s} at offset 0x{x}, size of {d} bytes and memory range of 0x{x}..0x{x}", .{
            section_name(
                &elfHdr,
                kernelImage,
                shdr.sh_name,
            ) orelse "<no name>",
            shdr.sh_offset,
            shdr.sh_size,
            shdr.sh_addr,
            shdr.sh_addr + shdr.sh_size,
        });
    }

    var phdrIter = elfHdr.iterateProgramHeadersBuffer(kernelImage);

    while (phdrIter.next() catch |e| {
        log.err("failed to parse program header: {s}", .{@errorName(e)});
        return errorCast(uefi.Error, e) orelse error.LoadError;
    }) |phdr| {
        if (phdr.p_type != std.elf.PT_LOAD) {
            log.warn("non loadable program header in kernel image of type 0x{x}", .{phdr.p_type});
            continue;
        }

        if (!PAGE_ALIGN.check(phdr.p_vaddr)) {
            log.err("load section start address not paged-aligned", .{});
            continue;
        }

        if (phdr.p_filesz > phdr.p_memsz) {
            log.err("load section is larger in image than in memory", .{});
            continue;
        }

        const pages = PAGE_ALIGN.forward(phdr.p_memsz) / 0x1000;

        log.info(
            "loading segment at offset 0x{x} and size of {d} bytes(file: {d} bytes) and memory range of 0x{x}..0x{x}",
            .{
                phdr.p_offset,
                phdr.p_memsz,
                phdr.p_filesz,
                phdr.p_vaddr,
                phdr.p_vaddr + (pages * 0x1000),
            },
        );

        const data = kernelImage[phdr.p_offset..(phdr.p_offset + phdr.p_filesz)];
        log.debug("first 8 bytes of data: {any}", .{data[0..8]});

        const backingMemory: []u8 = @ptrCast(try efiBootServices().allocatePages(
            .any,
            AntLoadedKernelMemory,
            pages,
        ));

        @memcpy(backingMemory.ptr, data);

        for (0..pages) |pgoff| {
            const addr: VirtualAddress = @bitCast(phdr.p_vaddr + (pgoff * 0x1000));
            const physAddr = @intFromPtr(backingMemory.ptr) + (pgoff * 0x1000);
            installMapping(addr, physAddr, .{
                .writable = (phdr.p_flags & std.elf.PF_W) > 0,
            }) catch |e| {
                log.err("failed to map segment: {s}", .{@errorName(e)});
                break;
            };
        }
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

    // up and down are reservsed

    log.info("setting up 28KiB init-bsp stack...", .{});
    const stackaddr = 0xFFFF_FFFF_FFFF_1000;
    const stacksize = 0x7000;

    const stackdata = @intFromPtr((try efiBootServices().allocatePages(
        .any,
        AntPreallocatedStackMemory,
        stacksize / 0x1000,
    )).ptr);

    for (0..(stacksize / 0x1000)) |pgoff| installMapping(
        @bitCast(stackaddr + (pgoff * 0x1000)),
        stackdata + (pgoff * 0x1000),
        .{ .writable = true },
    ) catch |e| {
        log.err("failed to map stac page: {s}", .{@errorName(e)});
        return errorCast(uefi.Error, e) orelse uefi.Error.Unexpected;
    };

    log.debug("identity mapping memory...", .{});

    for (0..(@"16GiB" / (2 * Mib))) |pfn| installMappingWithSize(
        @bitCast(pfn * (2 * Mib)),
        pfn * (2 * Mib),
        .{ .writable = true },
        .@"2M",
    ) catch |e| {
        log.err("failed to identity map large page (addr = 0x{x}): {s}", .{ pfn * Gib, @errorName(e) });
        return errorCast(uefi.Error, e) orelse uefi.Error.Unexpected;
    };

    var acpi_ptr: ?*anyopaque = null; 

    for (uefi.system_table.configuration_table[0..uefi.system_table.number_of_table_entries]) |*cfgtlb| {
        if (!cfgtlb.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) continue;

        acpi_ptr = cfgtlb.vendor_table;
    }

    // free all temporary allocations
    arena.deinit();

    const bootinfo: *BootInfo = @ptrCast(@alignCast(
        (allocatePages(1, .loader_data) catch return error.OutOfResources).ptr,
    ));

    log.debug("kernel handoff", .{});
    const info = try efiBootServices().getMemoryMapInfo();
    const mmapBuffer = uefi.pool_allocator.alignedAlloc(
        u8,
        .of(uefi.tables.MemoryDescriptor),
        (info.len + 1) * info.descriptor_size,
    ) catch return error.OutOfResources;
    const mmap = try efiBootServices().getMemoryMap(mmapBuffer);

    bootinfo.* = .{
        .size = @sizeOf(BootInfo),
        .kernel_image = .{
            .path = "<kernel>",
            .base = @intFromPtr(kernelImage.ptr),
            .size = kernelImage.len,
        },
        .memory = .{
            .descriptors = mmap.ptr,
            .descriptor_size = mmap.info.descriptor_size,
            .descriptor_count = mmap.info.len,
        },
        .acpi_ptr = acpi_ptr,
        .efi_ptr = uefi.system_table,
    };

    try efiBootServices().exitBootServices(uefi.handle, mmap.info.key);

    // !! NO PRINT AFTER THIS POINT !! //

    asm volatile (
        \\__kernel_handoff:
        \\cli
        \\movq %[pml4], %%cr3
        \\movq %[stacktop], %%rsp
        \\pushq %%r15
        // zero all regs expect for rsp(stack ptr) and rdi(bootinfo ptr).
        \\xorq %%rax, %%rax
        \\movq %%rax, %%rbx
        \\movq %%rax, %%rcx
        \\movq %%rax, %%rdx
        \\movq %%rax, %%rbp
        \\movq %%rax, %%rsi
        \\movq %%rax, %%r8
        \\movq %%rax, %%r9
        \\movq %%rax, %%r10
        \\movq %%rax, %%r11
        \\movq %%rax, %%r12
        \\movq %%rax, %%r12
        \\movq %%rax, %%r13
        \\movq %%rax, %%r14
        \\movq %%rax, %%r15
        \\retq
        :
        : [stacktop] "{rax}" (stackaddr + stacksize),
          [pml4] "{rbx}" (pml4.?),
          [bootinfo] "{rdi}" (bootinfo),
          [entry] "{r15}" (elfHdr.entry),
    );

    unreachable;
}

pub const BootInfo = extern struct {
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

    major_verion: usize = 0,
    minor_verion: usize = 1,
    size: usize,

    kernel_image: Image,
    memory: Memory,

    acpi_ptr: ?*anyopaque,
    efi_ptr: *uefi.tables.SystemTable,
};
