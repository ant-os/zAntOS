const std = @import("std");
const mm = @import("../mm.zig");
const vmm = @import("vmm.zig");

const log = std.log.scoped(.kheap);

const PAGE_SIZE = mm.PAGE_SIZE;

const HEAP_BASE = 0xFFFF_FFE0_0000_0000;
const HEAP_END = 0xFFFF_FFFF_0000_0000;
const HEAP_MAXIMUM_PAGES = ((0xFFFF_FFFF_0000_0000 - HEAP_BASE) / mm.PAGE_SIZE) - 1;
const HEAP_MINIMUM_SIZE = 0x10;
const HEAP_MAX_DENSITY_PER_PAGE = (PAGE_SIZE / (HEAP_MINIMUM_SIZE + @sizeOf(SegmentHeader))) + 2; // 1 extra just to be sure.

pub var vma = vmm.Area{
    .start = HEAP_BASE,
    .top = HEAP_BASE,
    .end = HEAP_END,
    .attrs = .{ .writable = true },
};

/// Heap segment header, located right before eveng:ry allocation.
const SegmentHeader = struct {
    const Header = @This();

    next: ?*SegmentHeader,
    prev: ?*SegmentHeader,
    free: bool,
    size: usize,
    padding: u32 = 0,

    /// get a pointer to the current segment.
    pub inline fn dataPointer(self: *Header) [*]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Header));
    }

    /// get the segment header from a segment data pointer.
    /// SAFETY: `data` MUST be a pointer to segment data as returned by `dataPointer()`.
    pub inline fn fromMemory(data: []u8) *SegmentHeader {
        return @ptrFromInt(@intFromPtr(data.ptr) - @sizeOf(Header));
    }

    /// splits the current segment into a two segment.
    /// if successful, the current segment has a  size given by `split_size`.
    /// and the second has the size of the remaining size of the current segment minus a new header.
    ///
    /// RETURN VALUE: if the split size is too small it returns null otherwise the second segment.
    pub fn split(self: *Header, split_size: usize) ?*SegmentHeader {
        if (split_size < HEAP_MINIMUM_SIZE) return null;
        if (split_size + @sizeOf(Header) >= self.size) return null; // Prevent invalid splitting

        const splitSegSize = self.size - split_size - @sizeOf(Header);

        if (splitSegSize <= 0) return null; // Prevent invalid segment creation

        const splitSeg: *SegmentHeader = @ptrFromInt(@intFromPtr(self) + @sizeOf(Header) + split_size);

        if (self.next != null) self.next.?.prev = splitSeg;
        splitSeg.next = self.next;

        self.next = splitSeg;
        self.size = split_size;

        splitSeg.prev = self;
        splitSeg.size = splitSegSize;
        splitSeg.free = true;

        if (lastSegment == self) lastSegment = splitSeg;

        return splitSeg;
    }

    /// combine the current and next segment if possible.
    /// SAFETY: invalidates all pointers to the next segment that already exist.
    /// RETURN VALUE: Returns self, e.g. a pointer to the current segment.
    pub fn combineForward(self: *SegmentHeader) ?*SegmentHeader {
        // if any of the next segment isn't free don't combine.
        const next = self.next orelse return null;
        if (!next.free) return null;

        const size = next.size + self.size + @sizeOf(SegmentHeader);
        if (next.next != null) next.next.?.prev = self;
        self.next = next.next;
        self.size = size;

        if (self.next == lastSegment) lastSegment = self;

        return self;
    }

    /// combine the current and last segment if possible.
    /// SAFETY: invalidates self, e.g. self should be consider uninitalized heap data.
    /// RETURN VALUE: A pointer to the "new" segment after backwards combine.
    pub fn combineBackwards(self: *SegmentHeader) ?*SegmentHeader {
        // if any of the two segment aren't free don't combine.
        if (!self.free) return null;
        const prev = self.prev orelse return null;
        if (!prev.free) return null;

        const size = prev.size + self.size + @sizeOf(SegmentHeader);
        if (self.next != null) self.next.?.prev = prev;
        prev.next = self.next;
        prev.size = size;

        if (self == lastSegment) lastSegment = prev;

        return prev;
    }
};

var lastSegment: ?*SegmentHeader = null;
var totalPages: usize = 0;

pub noinline fn init(preallocated_pages: usize) !void {
    log.info("Initalizing kernel heap with {d} preallocated page(s).", .{preallocated_pages});
    log.debug("Segment Header is {d} bytes.", .{@sizeOf(SegmentHeader)});

    try grow(preallocated_pages);
}

test "legacy tests" {
    var a = try allocator.alloc(u8, 8);
    a[0] = 23;
    a[1] = 25;
    var b = try allocator.alloc(u8, 4);
    b[3] = 54;
    b[2] = 56;
    log.debug("a = {any}", .{a});
    log.debug("b = {any}", .{b});
    dumpSegments();

    const aAddr = @intFromPtr(a.ptr);

    log.debug("freeing a and allocating c with a smaller size.", .{});

    allocator.free(a);
    // new allocation should be place at same place a was orginally.
    var c = try allocator.alloc(u8, 2);
    c[0] = 78;
    c[1] = 86;
    log.debug("c = {any}", .{c});

    if (@intFromPtr(c.ptr) != aAddr) {
        log.err("New allocation doesn't match with earlier freed allocation, found 0x{x} expected 0x{x}", .{
            @intFromPtr(c.ptr),
            aAddr,
        });
    }

    dumpSegments();

    const canResize = allocator.resize(c, 4);

    if (!canResize) {
        log.err(
            "Allocation should be able to be resized without realloc as it is placed in the first segment of larger freed segment",
            .{},
        );
    }

    log.debug("allocating 0x1234 bytes to cause heap to grow", .{});
    var mem = try allocator.alloc(u8, 0x1234);
    log.debug("mem = [{d}]{any}", .{ mem.len, mem.ptr });
    dumpSegments();

    log.debug("resize to 0x2000 bytes...", .{});
    if (!allocator.resize(mem, 0x2000)) log.err("failed to resize.", .{});

    mem = mem.ptr[0..0x2000];
    log.debug("mem = [{d}]{any}", .{ mem.len, mem.ptr });
    dumpSegments();

    // add more tests or seperate them into REAL tests.

    log.debug("Deallocating b and c...", .{});
    allocator.free(b);
    allocator.free(c);

    dumpSegments();
}

pub fn dumpSegments() void {
    var currentSeg = firstSegment();

    log.debug("DUMPING KERNEL HEAP SEGMENTS (size: {d} pages):", .{totalPages});

    while (true) {
        log.debug("{X} {s} {d} bytes", .{
            @intFromPtr(currentSeg.dataPointer()),
            if (currentSeg.free) "FREE" else "USED",
            currentSeg.size,
        });

        currentSeg = currentSeg.next orelse break;
    }
}

pub fn allocate(unaligned_size: usize, alignment: std.mem.Alignment, return_addr: usize) ![*]u8 {
    log.debug("allocate({d}, align: {any}) called.", .{ unaligned_size, alignment });
    _ = return_addr;

    var size = alignment.forward(unaligned_size);
    if (size < HEAP_MINIMUM_SIZE) size = HEAP_MINIMUM_SIZE;

    var currentSeg = firstSegment();
    var found = false;

    // NOTE: bounded loop to avoid possible infinite loops.
    for (0..((totalPages * HEAP_MAX_DENSITY_PER_PAGE) + 10)) |_| {
        if (currentSeg.free and currentSeg.size >= size) {
            found = true;
            break;
        }
        currentSeg = currentSeg.next orelse break;
    }

    if (!found) {
        const pageCount = (size / 0x1000) + 1;
        try grow(pageCount);

        currentSeg = lastSegment orelse unreachable;
    }

    const padding = alignment.forward(@intFromPtr(currentSeg)) - @intFromPtr(currentSeg);
    var prev = currentSeg.prev;
    var next = currentSeg.next;

    var newSegment: *SegmentHeader = @ptrFromInt(@intFromPtr(currentSeg) + padding);

    if (padding > std.math.maxInt(u16)) return error.InvalidAlignment;
    if (padding > 16) log.warn("Larger than 16-byte padding leaked ({d} bytes).", .{padding});
    newSegment.* = .{
        .size = size,
        .free = false,
        .prev = prev,
        .next = next,
        .padding = @intCast(padding),
    };
    if (prev != null) prev.?.next = newSegment;
    if (next != null) next.?.prev = newSegment;

    if (newSegment.size > size) _ = newSegment.split(size);

    //  return currentSeg.dataPointer(); // alignment!?!
    return newSegment.dataPointer();
}

fn vtable_alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, return_addr: usize) ?[*]u8 {
    return allocate(len, alignment, return_addr) catch null;
}

fn resize(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) bool {
    _ = ret_addr;

    var size = alignment.forward(new_len);
    if (size < HEAP_MINIMUM_SIZE) size = HEAP_MINIMUM_SIZE;

    log.debug("TRACE: resize([{d}]{any}, {d}) called", .{ memory.len, memory.ptr, size });

    const seg = SegmentHeader.fromMemory(memory);

    if (seg.size == size) return true;
    if (size < seg.size) {
        _ = seg.split(size);
        return true;
    }
    if (size > seg.size and seg.next != null and seg.next.?.free and (seg.size + seg.next.?.size + @sizeOf(SegmentHeader)) >= size) {
        _ = seg.combineForward();
        if (seg.size < size) return false; // just to be sure.
        _ = seg.split(size);
        return true;
    }

    if (seg == lastSegment and new_len > memory.len) {
        const inc = ((new_len - memory.len) / mm.PAGE_SIZE) + 1;
        grow(inc) catch return false;
        return true;
    }

    return false;
}

fn remap(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    log.debug("remap() called", .{});

    _ = memory;
    _ = alignment;
    _ = new_len;
    _ = ret_addr;

    return null;
}

fn grow(pages: usize) !void {
    try vma.grow(@intCast(pages));

    if (lastSegment != null) {
        lastSegment.?.size += pages * 0x1000;
    } else { // create a new last segment
        const newSeg: *SegmentHeader = @ptrFromInt(HEAP_BASE + (totalPages * 0x1000));

        newSeg.* = .{
            .next = null,
            .prev = lastSegment,
            .size = (pages * 0x1000) - @sizeOf(SegmentHeader),
            .free = true,
        };

        lastSegment = newSeg;
    }

    totalPages += pages;
}

fn free(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    ret_addr: usize,
) void {
    log.debug("free() called", .{});

    _ = alignment;
    _ = ret_addr;

    const seg = SegmentHeader.fromMemory(memory);
    seg.free = true;

    // ==== WARNING ====
    // combineBackwards may result in the freed segment becoming invalid
    // and MUST be the LAST place where "seg" is used.
    _ = seg.combineForward();
    _ = seg.combineBackwards();
    // ^ NOTE: we do not care about the return values
}

pub const allocator = std.mem.Allocator{ .ptr = undefined, .vtable = &std.mem.Allocator.VTable{
    .alloc = vtable_alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
} };

pub inline fn firstSegment() *SegmentHeader {
    return @ptrFromInt(HEAP_BASE);
}
