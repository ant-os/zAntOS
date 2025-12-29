const std = @import("std");
const mm = @import("paging.zig");
const pmm = @import("pageFrameAllocator.zig");
const klog = std.log.scoped(.kernel_heap);

const HEAP_BASE = 0xFFFF_FFE0_0000_0000;
const HEAP_SIZE = 0xFFFF_FFFF_0000_0000 - HEAP_BASE;
const HEAP_MINIMUM_SIZE = 0x10;

/// Heap segment header, located right before every allocation.
const SegmentHeader = struct {
    const Header = @This();

    next: ?*SegmentHeader,
    prev: ?*SegmentHeader,
    free: bool,
    size: usize,

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
        // if any of the two segment aren't free don't combine.
        if (!self.free) return null;
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

pub noinline fn init(preallocated_pages: usize) !void {
    klog.info("Initalizing kernel heap with {d} preallocated pages.", .{preallocated_pages});
    klog.debug("Segment Header is {d} bytes.", .{@sizeOf(SegmentHeader)});

    for (0..preallocated_pages) |idx| {
        try mm.mmMapPage(
            try pmm.pmmAllocatePage(),
            @ptrFromInt(HEAP_BASE + (idx * 0x1000)),
            .{ .writable = true },
        );
    }

    const startSeg = firstSegment();

    startSeg.* = .{
        .next = null,
        .prev = null,
        .size = (preallocated_pages * 0x1000) - @sizeOf(SegmentHeader),
        .free = true,
    };

    lastSegment = startSeg;

    klog.info("Done with heap init.", .{});

    var a = try allocator.alloc(u8, 8);
    a[0] = 23;
    a[1] = 25;
    var b = try allocator.alloc(u8, 4);
    b[3] = 54;
    b[2] = 56;
    klog.debug("a = {any}", .{a});
    klog.debug("b = {any}", .{b});
    dumpSegments();

    const aAddr = @intFromPtr(a.ptr);

    klog.debug("freeing a and allocating c with a smaller size.", .{});

    allocator.free(a);
    // new allocation should be place at same place a was orginally.
    var c = try allocator.alloc(u8, 2);
    c[0] = 78;
    c[1] = 86;
    klog.debug("c = {any}", .{c});

    if (@intFromPtr(c.ptr) != aAddr) {
        klog.err("New allocation doesn't match with earlier freed allocation, found 0x{x} expected 0x{x}", .{
            @intFromPtr(c.ptr),
            aAddr,
        });
    }

    dumpSegments();

    klog.debug("note: not yet implemented function usage below:", .{});
    const canResize = allocator.resize(c, 4);

    if (!canResize) {
        klog.err(
            "Allocation should be able to be resized without realloc as it is placed in the first segment of larger freed segment",
            .{},
        );
    }

    // add more tests or seperate them info REAL tests.

    klog.debug("Deallocating b and c...", .{});
    allocator.free(b);
    allocator.free(c);

    dumpSegments();
}

fn dumpSegments() void {
    var currentSeg = firstSegment();

    klog.debug("DUMPING KERNEL HEAP SEGMENTS:", .{});

    while (true) {
        klog.debug("{X} {s} {d} bytes", .{
            @intFromPtr(currentSeg.dataPointer()),
            if (currentSeg.free) "FREE" else "USED",
            currentSeg.size,
        });

        currentSeg = currentSeg.next orelse break;
    }
}

fn allocate(_: *anyopaque, len: usize, alignment: std.mem.Alignment, return_addr: usize) ?[*]u8 {
    // klog.debug("allocate called.", .{});

    _ = return_addr;

    var size = alignment.forward(len);
    if (size < HEAP_MINIMUM_SIZE) size = HEAP_MINIMUM_SIZE;

    var currentSeg = firstSegment();

    while (true) {
        if (currentSeg.free) {
            if (currentSeg.size > size) {
                _ = currentSeg.split(size);
                currentSeg.free = false;
                return currentSeg.dataPointer(); // TODO: alignment?
            }
            if (currentSeg.size == size) {
                currentSeg.free = false;
                return currentSeg.dataPointer();
            }
        }
        if (currentSeg.next == null) break;

        currentSeg = currentSeg.next.?;
    }

    return null;
}

fn resize(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) bool {
    klog.debug("resize() called", .{});
    _ = memory;
    _ = alignment;
    _ = new_len;
    _ = ret_addr;

    return false;
}
fn remap(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    klog.debug("remap() called", .{});

    _ = memory;
    _ = alignment;
    _ = new_len;
    _ = ret_addr;

    return null;
}

fn free(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    ret_addr: usize,
) void {
    klog.debug("free() called", .{});

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
    .alloc = allocate,
    .resize = resize,
    .remap = remap,
    .free = free,
} };

pub inline fn firstSegment() *SegmentHeader {
    return @ptrFromInt(HEAP_BASE);
}
