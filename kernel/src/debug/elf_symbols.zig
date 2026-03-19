//! ELF Symbols

const std = @import("std");
const bootmem = @import("../mm/bootmem.zig");
const bootloader = @import("../bootloader.zig");
const options = @import("options");
const logger = @import("../logger.zig");

const log = std.log.scoped(.elf_symbols);

const MAX_INITRD_FILENAME_LEN = 120;

// get the kernel image as a byte-slice.
pub noinline fn kernel_image() ![]const u8 {
    return bootloader.info.kernel_image.base[0..bootloader.info.kernel_image.size];
}

pub inline fn section_header(header: *const std.elf.Header, buffer: []const u8, index: u32) ?*const std.elf.Shdr {
    if (index > header.shnum) return null;
    const offset = header.shoff + @sizeOf(std.elf.Shdr) * index;
    return @ptrCast(@alignCast(&buffer[offset]));
}

pub inline fn section_name(header: *const std.elf.Header, buffer: []const u8, index: u32) ?[]const u8 {
    if (index == 0) return null;
    const shstr = section_header(
        header,
        buffer,
        header.shstrndx,
    ).?;

    return strtab_get(buffer, shstr, index);
}

pub inline fn sectionNameZ(header: *const std.elf.Header, buffer: []const u8, index: u32) ?[*:0]const u8 {
    if (index == 0) return null;
    const shstr = section_header(
        header,
        buffer,
        header.shstrndx,
    ).?;

    return strtabGetZ(buffer, shstr, index);
}

pub inline fn strtabGetZ(buffer: []const u8, tab: *const std.elf.Shdr, index: u32) ?[*:0]const u8 {
    if (index == 0) return null;

    if (index >= tab.sh_size) return null;

    return @ptrCast(buffer[tab.sh_offset + index ..].ptr);
}

pub inline fn strtab_get(buffer: []const u8, tab: *const std.elf.Shdr, index: u32) ?[]const u8 {
    if (index == 0) return null;

    if (index >= tab.sh_size) return null;

    const name: [*c]const u8 = buffer[tab.sh_offset + index ..].ptr;

    return name[0..std.mem.len(name)];
}

pub inline fn section_by_name(
    header: *const std.elf.Header,
    buffer: []const u8,
    name: []const u8,
) ?*const std.elf.Shdr {
    for (0..header.shnum) |i| {
        const hdr = section_header(header, buffer, @intCast(i)).?;
        const sh_name = section_name(header, buffer, hdr.sh_name) orelse continue;
        if (std.mem.eql(u8, sh_name, name)) {
            return hdr;
        }
    }

    return null;
}

var elfhdr: std.elf.Header = undefined;
var strtab: *const std.elf.Shdr = undefined;
var symbols: []const std.elf.Sym = undefined;
var image: []const u8 = undefined;
var initalized: bool = false;

pub const Resolved = struct { name: []const u8, offset: usize };
pub inline fn resolve(addr: usize) ?Resolved {
    if (!initalized) return null;

    for (symbols) |sym| {
        const end = sym.st_value + sym.st_size;
        if (addr >= sym.st_value and addr <= end) return .{
            .name = strtab_get(image, strtab, sym.st_name) orelse "<unnamed>",
            .offset = addr - sym.st_value,
        };
    }

    return null;
}

pub noinline fn init() !void {
    image = try kernel_image();
    var r: std.io.Reader = .fixed(image);

    elfhdr = try std.elf.Header.read(&r);

    log.info("kernel elf header: {any}", .{&elfhdr});

    var sh_iter = elfhdr.iterateSectionHeadersBuffer(image);

    while (try sh_iter.next()) |sh| {
        log.info("found section {s}", .{
            section_name(&elfhdr, image, sh.sh_name) orelse "<no name>",
        });
    }

    const symtab = section_by_name(
        &elfhdr,
        image,
        ".symtab",
    ) orelse return error.SymtabNotFound;

    std.log.info("symtab = {any}", .{symtab});

    strtab = section_by_name(
        &elfhdr,
        image,
        ".strtab",
    ) orelse return error.SymtabNotFound;

    if (symtab.sh_type != std.elf.SHT_SYMTAB)
        return error.InvalidSymtab;

    if (strtab.sh_type != std.elf.SHT_STRTAB)
        return error.InvalidStrtab;

    const symbol_count = symtab.sh_size / @sizeOf(std.elf.Sym);
    const symtab_data: [*]const std.elf.Sym = @ptrCast(@alignCast(image[symtab.sh_offset..]));
    symbols = symtab_data[0..symbol_count];

    log.debug("total of {d} ELF symbols found\n\r", .{symbol_count});

    initalized = true;
}

const ktest = @import("../ktest.zig");

export fn test_symbol() void {
    std.debug.assert(ktest.enabled);
    asm volatile ("nop");
}

test test_symbol {
    std.mem.doNotOptimizeAway(test_symbol());
}

test resolve {
    const resolved = resolve(@intFromPtr(&test_symbol) + 1).?;

    try ktest.expectEqualString(resolved.name, "test_symbol");
}
