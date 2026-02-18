const std = @import("std");
const pfmdb = @import("pfmdb.zig");
const paging = @import("paging.zig");
const pframe_alloc = @import("pframe_alloc.zig");
const mm = @import("../mm.zig");

pub const Area = struct {
    start: u64,
    end: u64,
    top: u64,

    tag: u8 = 0,
    flags: u8 = 0,
    free: bool = false,
    attrs: paging.PageAttributes = .{},

    node: std.DoublyLinkedList.Node = .{},
    backing_frame_count: u32 = 0,
    backing_frames: std.DoublyLinkedList = .{},

    pub inline fn isFree(self: *const Area) bool {
        return self.free;
    }

    pub inline fn next(self: *const Area) ?*Area {
        const nextNode = self.node.next orelse return null;
        return @fieldParentPtr("node", nextNode);
    }

    pub inline fn prev(self: *const Area) ?*Area {
        const prevNode = self.node.prev orelse return null;
        return @fieldParentPtr("node", prevNode);
    }

    pub inline fn isMapped(self: *const Area) bool {
        return self.backing_frame_count > 0 and self.first_backing_frame != .invalid;
    }


    pub inline fn firstMapping(self: *const Area) ?*const pfmdb.PageFrame {
        if (self.backing_frames.first == null) return null;
        return @fieldParentPtr("node", self.backing_frames.first.?);
    }

    pub noinline fn grow(self: *Area, pages: u32) !void {
        const newTop = self.top + (pages * mm.PAGE_SIZE);
        var unmapped = pages;

        if (newTop > self.end) return error.VmmOutOfSpace;
    
        while (unmapped > 0) {
            const order: mm.Order = .newTruncated(std.math.log2_int(u32, unmapped));
            const frame = blk: {
                const tok = pfmdb.lock();
                defer tok.release();

                const pfn = try pframe_alloc.allocOrder(order, tok);
                break :blk pfn.frameMut(tok).?;
            };

            std.debug.assert(frame.getState() == .used);

            try internalMapFrame(frame, self.top, self.attrs);

            {
                const tok  = pfmdb.lock();
                defer tok.release();

                self.backing_frame_count += 1;
                self.backing_frames.append(&frame.node);
            }

            unmapped -= order.totalPages();
        }

        self.top = newTop;
    }
};


fn internalMapFrame(frame: *const pfmdb.PageFrame, virtualAddr: u64, attrs: paging.PageAttributes) !void {
    const physAddr = frame.pfn().?.toPhysicalAddr().raw;
    return paging.mapRegion(physAddr, virtualAddr, frame.totalPages(), attrs);
}
