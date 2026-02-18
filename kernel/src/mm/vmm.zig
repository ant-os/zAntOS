const std = @import("std");
const pfmdb = @import("pfmdb.zig");

pub const AddressSpace = struct {
    vm_areas: std.DoublyLinkedList,

    pub fn areaFromAddress(self: *const AddressSpace, addr: u64) ?*const Area {
        var area = self.firstArea() orelse return null;

        while (area.next()) |nextArea| {
            if (addr >= area.start and addr < area.end) return area;
            area = nextArea;
        }

        return null;
    }

    pub fn firstArea(self: *const AddressSpace) ?*const Area {
        if (self.vm_areas.first == null) return null;
        return @fieldParentPtr("node", self.vm_areas.first.?);
    }

    pub fn lastArea(self: *const AddressSpace) ?*const Area {
        if (self.vm_areas.last == null) return null;
        return @fieldParentPtr("node", self.vm_areas.last.?);
    }
};

pub const Area = struct {
    start: u64,
    end: u64,
    top: u64,

    tag: u8,
    flags: u8,
    free: bool,
    unused1: u8,
    unused2: u32,

    node: std.DoublyLinkedList.Node,
    backing_frame_count: u32,
    first_backing_frame: pfmdb.Pfn = .invalid,

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
};
