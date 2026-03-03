//! Boot Memory ALlocator
//! 
//! A fixed buffer allocator for the biggest free physical memory region found
//! in the efi memory map provided by the loader (antboot2).
//! 
//! It also has an enabled flag and all allocator functions panic if enabled is false.
//! 
//! BOOTMEM can be disabled using the disable() function which will return the slice of memory used
//! for possible reserving of that region in later-stage allocators for physical memory.
//! 

const std = @import("std");
const builtin = @import("builtin");
const bootloader = @import("../bootloader.zig");
const mm = @import("../mm.zig");

const log = std.log.scoped(.bootmem);

var enabled: bool = false;
var alloc: std.heap.FixedBufferAllocator = undefined;
var seal_base_allocs: ?usize = null;
var num_allocs: usize = 0;
var selected_mmap_entry: usize = 0;

pub noinline fn enterSealedRegion() void {
    if (builtin.mode != .Debug) return;
    
    if (!enabled) @panic("bootmem not enabled");
    if (seal_base_allocs != null) @panic("already in sealed region");

    seal_base_allocs = num_allocs;
}

pub noinline fn leaveAndDetectLeaks() void {
    if (builtin.mode != .Debug) return;

    if (seal_base_allocs == null) @panic("not not in sealed region"); 

//    std.log.debug("region = {d}, endidx = {d}", .{region.?, alloc.end_index});
    if (num_allocs > seal_base_allocs.?) @panic("bootmem memory leak detected");

    seal_base_allocs = null;
}

pub noinline fn managesPointer(ptr: u64) bool {
    @setRuntimeSafety(false);
    return alloc.ownsPtr(@ptrFromInt(ptr));
} 

pub inline fn startsAt(ptr: u64) bool {
    const current: u64 = @intFromPtr(alloc.buffer.ptr);
    return current == ptr;
}

pub fn init() !void {
    if (enabled) return error.AlreadyEnabled;

    var largest_region: u64 = 0;
    var largest_number_of_pages: u64 = 0;

    var iter: std.os.uefi.tables.MemoryDescriptorIterator = bootloader.memoryDescriptorIter();

    while (iter.next()) |r| {
        if (r.type != .conventional_memory) continue;
        if (r.number_of_pages < largest_number_of_pages) continue;

        largest_region = r.physical_start;
        largest_number_of_pages = r.number_of_pages;
    }

    if (largest_number_of_pages == 0 or largest_region == 0)
        return error.NotEnoughtPhysicalMemory;

    log.info("using physical region at 0x{x} with size of {d} pages.", .{ largest_region, largest_number_of_pages });

    const base_ptr: [*]u8 = @ptrFromInt(largest_region);

    alloc = .init(base_ptr[0..(largest_number_of_pages * 0x1000)]);
    enabled = true;
}

pub fn disable() ?struct { mm.PhysicalAddr, u32 } {
    if (!enabled) return null;
    enabled = false;

    const pages = mm.PAGE_ALIGN.forward(alloc.end_index) >> mm.PAGE_SHIFT;

    return .{ .{ .raw = @intFromPtr(alloc.buffer.ptr) }, @intCast(pages) }; 
}

pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &std.mem.Allocator.VTable{
        .alloc = &vt_alloc,
        .free =  &vt_free,
        .remap = &vt_remap,
        .resize = &vt_resize,
    },
};

fn vt_alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    if (!enabled) @panic("bootmem not enabled");

    num_allocs += 1;

    return alloc.allocator().rawAlloc(len, alignment, ret_addr);
}

fn vt_free(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    if (!enabled) @panic("bootmem not enabled");

    if (num_allocs == 0 and builtin.mode == .Debug) @panic("bootmem double free detected");

    num_allocs -= 1;

    return alloc.allocator().rawFree(memory, alignment, ret_addr);
}

fn vt_remap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    if (!enabled) @panic("bootmem not enabled");

    return alloc.allocator().rawRemap(memory, alignment, new_len, ret_addr);
}

fn vt_resize(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    if (!enabled) @panic("bootmem not enabled");

    return alloc.allocator().rawResize(memory, alignment, new_len, ret_addr);
}
