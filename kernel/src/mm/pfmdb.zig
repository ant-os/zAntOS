//! Page Frame Manager Database
//!

const std = @import("std");
const ktest = @import("../ktest.zig");
const bootldr = @import("../bootloader.zig");
const bootmem = @import("bootmem.zig");
const mm = @import("../mm.zig");
const SpinLock = @import("../sync/spin_lock.zig").SpinLock;
const log = std.log.scoped(.pfmdb);

var pfmdb_array: ?[]PageFrame = null;
var global_lock: SpinLock = .{};

pub inline fn baseAddress() u64 {
    return @intFromPtr(pfmdb_array.?.ptr);
}

pub inline fn isInitalized() bool {
    return pfmdb_array != null;
}

/// zero-bit marker type that allows write access to the global pfmdb.
pub const WriteToken = struct {
    /// **THIS MUST NEVER BE USED OUTSIDE OF `PFMDB` INTERNALS.**
    ///
    /// To get WriteToken use pfmdb.lock() instead as field-init is UB.
    __internal_do_not_use_directly_otherwise_ub__: void,

    pub fn release(self: WriteToken) void {
        log.debug("token released", .{});
        unlock(self);
    }
};

pub fn lock() WriteToken {
    log.debug("pfmdb locked", .{});
    global_lock.lock();
    return .{ .__internal_do_not_use_directly_otherwise_ub__ = undefined };
}

pub fn unlock(token: WriteToken) void {
    _ = token;
    global_lock.unlock();
}

pub const Pfn = enum(u32) {
    @"null" = 0,
    invalid = std.math.maxInt(u32),
    _,

    pub inline fn distanceFromEnd(self: Pfn) u32 {
        if (!self.isValid()) return 0;
        return pfmdb_array.?.len - self.raw();
    }

    pub inline fn toPhysicalAddr(self: Pfn) mm.PhysicalAddr {
        return .{ .typed = .{ .pfn = self } };
    }

    pub inline fn releativeTo(self: Pfn, other: Pfn) ?ReleativePfn {
        if (self.raw() < other.raw()) return null;
        const dist = self.raw() - other.raw();
        return .{ .base = other, .offset = dist };
    }

    pub inline fn releative(self: Pfn, offset: u32) ReleativePfn {
        return .{ .base = self, .offset = offset };
    }

    pub inline fn raw(self: Pfn) u32 {
        return @intFromEnum(self);
    }

    pub inline fn root(self: Pfn) Pfn {
        return self.frame().?.root();
    }

    pub inline fn isFree(self: Pfn) bool {
        return self.frame().?.state == .free;
    }

    pub inline fn maximumOrder(self: Pfn) ?mm.Order {
        return (self.frame() orelse return null).info.maximum_order;
    }

    pub inline fn next(self: Pfn) !Pfn {
        if (!self.isValid()) return error.InvalidPfn;
        return .new(self.raw() + 1) orelse return error.OutOfBounds;
    }

    pub fn frame(self: Pfn) ?*const PageFrame {
        return self.frameInner();
    }

    pub fn frameMut(self: Pfn, token: WriteToken) ?*PageFrame {
        _ = token;

        return self.frameInner();
    }

    fn frameInner(self: Pfn) ?*PageFrame {
        if (!self.isValid()) return null;
        return &pfmdb_array.?[self.raw()];
    }

    pub inline fn isValid(self: Pfn) bool {
        std.debug.assert(pfmdb_array != null);
        return self.raw() < pfmdb_array.?.len;
    }

    pub inline fn assertValid(self: Pfn) void {
        if (ktest.enabled and !self.isValid()) @panic("invalid page frame number");
    }

    pub fn buddyForOrder(self: Pfn, order: mm.Order) ?Pfn {
        self.assertValid();

        if (order.raw().? >= self.maximumOrder().?.raw().?) return null;

        var rel: ReleativePfn = self.releativeTo(self.root()) orelse return null;

        rel.offset ^= order.totalPages();

        return rel.absolute();
    }

    pub inline fn new(v: u32) ?Pfn {
        if (v >= pfmdb_array.?.len) return null;
        return @enumFromInt(v);
    }
};

pub const ReleativePfn = struct {
    base: Pfn,
    offset: u32,

    pub fn absolute(self: ReleativePfn) ?Pfn {
        self.base.assertValid();
        if (self.base.frame().?.getState() == .free) std.debug.assert((self.offset <= self.base.frame().?.info.maximum_order.totalPages()));
        const isroot = self.base.frame().?.info.flags.root;
        const origin = if (isroot) self.base.raw() else self.base.frame().?.origin.raw();
        return .new(origin + self.offset);
    }
};

pub const PageFrameTag = enum(u8) { unused = 0, normal, static, _ };

pub const PageFrameState = enum(u8) {
    not_present = 0,
    free = 1,
    used = 2,
    reserved = 0xFF,
    _,
};

pub const PageFrame = struct {
    pub const Info = packed struct(u64) {
        order: mm.Order,
        maximum_order: mm.Order,
        flags: packed struct(u6) {
            root: bool,
            isReserved: bool,
            reserved: u4 = 0,
        },
        tag: PageFrameTag = .normal,
        active: bool = true,
        _unused: u7 = 0,
        refcount: u32 = 0,
    };

    info: Info,
    node: std.DoublyLinkedList.Node,
    origin: Pfn,

    pub fn next(self: *const PageFrame) ?*const PageFrame {
        if (self.node.next == null) return null;
        return @fieldParentPtr("node", self.node.next.?);
    }

    pub inline fn getState(self: *const PageFrame) PageFrameState {
        if (!self.info.active) return .not_present;
        if (self.info.flags.isReserved) return .reserved;
        return if (self.info.refcount >= 1) .used else .free;
    }

    pub inline fn upgradeToMut(self: *const PageFrame, tok: WriteToken) *PageFrame {
        _ = tok;

        return @constCast(self);
    }

    pub inline fn root(self: *const PageFrame) Pfn {
        std.debug.assert(self.getState() != .not_present);
        return if (self.info.flags.root) self.pfn().? else self.origin;
    }

    pub inline fn pfn(self: *const PageFrame) ?Pfn {
        const elem = @intFromPtr(self);
        const base = @intFromPtr(pfmdb_array.?.ptr);

        if (elem < base) return null;

        const index = (elem - base) / @sizeOf(PageFrame);

        return Pfn.new(@truncate(index));
    }

    pub fn totalPages(self: *const PageFrame) usize {
        return @intCast(self.info.order.totalPages());
    }

    test pfn {
        const expected_pfn, const frame = testing_GetPfnAndFrame(totalManagablePages() / 3);

        try ktest.expectExtended(
            .{ .expected_pfn = expected_pfn, .pfn = frame.pfn() },
            @src(),
            frame.pfn() == expected_pfn,
        );

        const outside_frame = ktest.mkStaticValuePtr(@as(PageFrame, undefined));

        try ktest.expectExtended(
            .{},
            @src(),
            outside_frame.pfn() == null,
        );
    }

    // ...
};

pub fn totalManagablePages() u32 {
    return @truncate(pfmdb_array.?.len);
}

fn testing_GetPfnAndFrame(idx: u32) struct { Pfn, *PageFrame } {
    return .{ @enumFromInt(idx), &pfmdb_array.?[idx] };
}

pub fn init() !void {
    if (pfmdb_array != null) @panic("pfmdb already initialized");

    const pages = bootldr.totalPhysicalPagesWithHoles();
    log.info("Initializing PFMDB for {d} physical pages", .{pages});

    pfmdb_array = try bootmem.allocator.alloc(PageFrame, pages);

    @memset(std.mem.sliceAsBytes(pfmdb_array.?), 0x0);

}
