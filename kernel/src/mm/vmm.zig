const std = @import("std");
const pfmdb = @import("pfmdb.zig");
const paging = @import("paging.zig");
const pframe_alloc = @import("pframe_alloc.zig");
const mm = @import("../mm.zig");
const heap = @import("heap.zig");
const queue = @import("../utils/queue.zig");
const SpinLock = @import("../sync/spin_lock.zig").SpinLock;

pub const AreaList = queue.DoublyLinkedList(Area, "node");

pub var kernel_areas: AreaList = .{
    .impl = .{
        .head = &noncanonical_area.node,
        .tail = &noncanonical_area.node,
        .len = 1,
    },
};

pub var global_lock: SpinLock = .{};

var noncanonical_area: Area = .{
    .start = 0x0000_8000_0000_0000,
    .top = 0xFFFF_8000_0000_0000,
    .end = 0xFFFF_8000_0000_0000,
    .attrs = .{
        .writable = false,
    },
    .tag = .{ .known = .invalid },
};

pub const Tag = extern union {
    comptime {
        std.debug.assert(@bitSizeOf(Tag) == 64);
    }

    uint: u64,
    string: [8]u8,
    known: enum(u64) {
        untagged = 0x0,
        max = std.math.maxInt(u64),
        normal = std.mem.bytesToValue(u64, "NORMAL  "),
        invalid = std.mem.bytesToValue(u64, "INVALID "),
        _,
    },

};

pub const Area = struct {
    start: u64,
    end: u64,
    top: u64,

    tag: Tag = .{ .known = .normal },
    flags: u8 = 0,
    attrs: paging.PageAttributes = .{},

    node: queue.DoublyLinkedNode = .{},
    backing_frame_count: u32 = 0,
    backing_frames: std.DoublyLinkedList = .{},

    pub fn allocate(
        pages: usize,
        min_address: usize,
        max_address: usize,
        attributes: paging.PageAttributes,
        tag: Tag,
    ) !*Area {
        const before = try findAreaBeforeGap(pages, min_address, max_address);

        const start = @max(min_address, before.end);
        const end = start + (pages * mm.PAGE_SIZE);

        const self = try heap.allocator.create(Area);
        self.* = .{
            .start = start,
            .end = end,
            .top = start,
            .attrs = attributes,
            .tag = tag,
        };

        try self.grow(pages);

        try insertKernelArea(self);

        return self;
    }

    pub fn findAreaBeforeGap(
        pages: u64,
        min_address: usize,
        max_address: usize,
    ) !*Area {
        const size = pages * mm.PAGE_SIZE;
        if ((min_address + size) > max_address) return error.InvalidParamter;

        var current = kernel_areas.peek_front();
        var next = AreaList.next(current.?);

        while (current) |area| : ({
            current = next;
            next = AreaList.next(area);
        }) {
            const gapEnd = if (next != null) next.?.start else std.math.maxInt(u64);
            const gapSize = gapEnd - area.end;
            if (size <= gapSize) return area;
        }
        return error.OutOfMemory;
    }

    pub fn asPointer(self: *const Area) [*]u8 {
        return @ptrFromInt(self.start);
    }

    pub fn insertKernelArea(area: *Area) !void {
        if (area.start < 0xFFFF_0000_0000_0000) return error.InvalidParameter;

        global_lock.lock();
        defer global_lock.unlock();

        if (kernel_areas.length() == 0) {
            kernel_areas.add_front(area);
            return;
        }

        const pages = (area.end - area.start) >> mm.PAGE_SHIFT;
        const gap = (try findAreaBeforeGap(pages, area.start, area.end));
        kernel_areas.add_after(gap, area);
    }

    pub inline fn isMapped(self: *const Area) bool {
        return self.backing_frame_count > 0 and self.first_backing_frame != .invalid;
    }

    pub inline fn firstMapping(self: *const Area) ?*const pfmdb.PageFrame {
        if (self.backing_frames.first == null) return null;
        return @fieldParentPtr("node", self.backing_frames.first.?);
    }

    pub noinline fn grow(self: *Area, pages: u64) !void {
        const newTop = self.top + (pages * mm.PAGE_SIZE);
        var unmapped = pages + 1;

        if (newTop > self.end) return error.VmmOutOfSpace;

        while (unmapped > 0) {
            const order: mm.Order = .newTruncated(@intCast(std.math.log2_int(u64, unmapped)));
            const frame = blk: {
                const tok = pfmdb.lock();
                defer tok.release();

                const pfn = try pframe_alloc.allocOrder(order, tok);
                break :blk pfn.frameMut(tok).?;
            };

            std.debug.assert(frame.getState() == .used);

            try internalMapFrame(frame, self.top, self.attrs);

            {
                const tok = pfmdb.lock();
                defer tok.release();

                self.backing_frame_count += 1;
                self.backing_frames.append(&frame.node);
            }

            unmapped -= order.totalPages();
            self.top += (order.totalPages() * 0x1000);
        }

        self.top = newTop;
    }
};

fn internalMapFrame(frame: *const pfmdb.PageFrame, virtualAddr: u64, attrs: paging.PageAttributes) !void {
    const physAddr = frame.pfn().?.toPhysicalAddr().raw;
    return paging.mapRegion(physAddr, virtualAddr, frame.totalPages(), attrs);
}
