//! Physical Frame ALlocator
//!

const std = @import("std");
const mm = @import("../mm.zig");
const pfmdb = @import("pfmdb.zig");
const bootldr = @import("../bootloader.zig");
const bootmem = @import("bootmem.zig");

const assert = std.debug.assert;
const log = std.log.scoped(.pframe_alloc);
const Limit = std.Io.Limit;

var global_freelists: [mm.Order.raw_max + 1]std.DoublyLinkedList = .{std.DoublyLinkedList{}} ** (mm.Order.raw_max + 1);
var totalFreePages: std.atomic.Value(u32) = .init(0);
var totalUsedPages: std.atomic.Value(u32) = .init(0);
var totalReservedPages: std.atomic.Value(u32) = .init(0);

fn initPageFrame(
    frame: *pfmdb.PageFrame,
    order: mm.Order,
    tag: pfmdb.PageFrameTag,
    origin: pfmdb.Pfn,
    root: bool,
) !void {
    const max_order = if (root) order else getRootOrder: {
        const real_root = origin.frame() orelse return error.InvalidRoot;
        break :getRootOrder real_root.info.maximum_order;
    };

    if (!root) log.debug(
        "initalizing {s} page frame at PFN {d} with order {any}(max {any}), origin frame of {any}, tagged {s}.",
        .{
            if (root) "root" else "leaf",
            frame.pfn().?.raw(),
            order.raw(),
            max_order.raw(),
            origin.raw(),
            @tagName(tag),
        },
    );

    frame.* = .{
        .info = .{
            .tag = tag,
            .order = order,
            .maximum_order = max_order,
            .flags = .{ .root = root, .isReserved = false },
        },
        .origin = origin,
        .node = .{}
    };
}

pub inline fn getGlobalFreelistForOrder(order: mm.Order) ?*std.DoublyLinkedList {
    return &global_freelists[order.raw() orelse return null];
}

pub fn getBuddyOfPfnForOrder(pfn: pfmdb.Pfn, order: mm.Order) ?pfmdb.Pfn {
    pfn.assertValid();

    if (order.raw().? >= pfn.maximumOrder().?.raw().?) return null;

    var rel: pfmdb.ReleativePfn = pfn.releativeTo(pfn.root()) orelse return null;

    rel.offset ^= order.totalPages();

    return rel.absolute();
}

pub fn splitFrameAssumeUnused(frame: *pfmdb.PageFrame, tok: pfmdb.WriteToken) !void {
    log.debug("trying to split frame at PFN {d} with order {any}", .{
        frame.pfn().?.raw(),
        frame.info.order.raw(),
    });
    std.debug.assert(frame.getState() != .not_present);

    const order = frame.info.order.sub(1) orelse return error.PageFrame;
    const buddy = getBuddyOfPfnForOrder(frame.pfn().?, order) orelse return error.NoBuddyFrameFound;

    frame.info.order = order;
    const bfp = buddy.frameMut(tok).?;

    try initPageFrame(
        bfp,
        order,
        .normal,
        frame.root(),
        false,
    );

    markFreeWithFreelist(bfp);
}

inline fn markUsed(frame: *pfmdb.PageFrame) void {
    std.debug.assert(frame.info.refcount == 0);
    if (frame.getState() == .free) _ = totalFreePages.fetchSub(frame.info.order.totalPages(), .monotonic);
    _ = totalUsedPages.fetchAdd(frame.info.order.totalPages(), .monotonic);
    frame.info.active = true;
    frame.info.refcount = 1;
}

inline fn markReserved(frame: *pfmdb.PageFrame) void {
    if (frame.getState() == .free) _ = totalFreePages.fetchSub(frame.info.order.totalPages(), .monotonic);
    _ = totalReservedPages.fetchAdd(frame.info.order.totalPages(), .monotonic);
    frame.info.active = true;
    frame.info.refcount = 1;
    frame.info.tag = .static;
}

inline fn markFreeWithFreelist(frame: *pfmdb.PageFrame) void {
    if (frame.getState() == .used) _ = totalUsedPages.fetchSub(frame.info.order.totalPages(), .monotonic);
    _ = totalFreePages.fetchAdd(frame.info.order.totalPages(), .monotonic);
    if (frame.info.refcount > 0) frame.info.refcount -= 1;
    std.debug.assert(frame.info.refcount == 0);
    frame.node = .{};
    getGlobalFreelistForOrder(frame.info.order).?.append(&frame.node);
}

fn initalizeRegionRoots(
    origin: pfmdb.Pfn,
    pages: u32,
    state: pfmdb.PageFrameState,
    tok: pfmdb.WriteToken,
    upper_region: ?pfmdb.Pfn,
    kind: pfmdb.PageFrameTag,
) !u32 {
    const order: mm.Order = .newTruncated(std.math.log2_int(u32, pages));
    const next_region = origin.releative(order.totalPages());
    const frame = origin.frameMut(tok).?;
    const leftover = pages - order.totalPages();

    log.debug(
        "initalizing {s} root page frame at PFN {d}, order {any}, tagged {s}",
        .{ @tagName(state), frame.pfn().?.raw(), order.raw(), @tagName(kind) },
    );

    try initPageFrame(
        frame,
        order,
        kind,
        upper_region orelse .invalid,
        true,
    );

    switch (state) {
        .reserved => markReserved(frame),
        .used => markUsed(frame),
        .free => markFreeWithFreelist(frame),
        else => return error.InvalidPageState,
    }

    // _ = leftover;
    // _ = next_region;
    if (leftover == 0) return order.totalPages();

    // sweep
    return if (next_region.absolute()) |next| try initalizeRegionRoots(
        next,
        leftover,
        state,
        tok,
        upper_region,
        kind,
    ) + order.totalPages() else order.totalPages();
}

pub fn allocAny(pages: u32, tok: pfmdb.WriteToken) !pfmdb.Pfn {
    const order = mm.Order.new(
        @truncate(std.math.log2_int_ceil(u32, pages)),
    ) orelse return error.UnsupportedParameterValue;

    return try allocOrder(order, tok);
}

pub fn lockAndAllocAny(pages: u32) !pfmdb.Pfn {
    const tok = pfmdb.lock();
    defer tok.release();

    return allocAny(pages, tok);
}

pub fn allocExactOrder(order: mm.Order, tok: pfmdb.WriteToken) !pfmdb.Pfn {
    if (!order.isValid()) return error.InvalidOrder;

    const freelist = getGlobalFreelistForOrder(order).?;

    const frame = frameFormFreelistNode(freelist.pop() orelse return error.AllocFailed, tok);

    std.debug.assert(frame.getState() == .free);
    std.debug.assert(frame.info.order == order);

    try markUsedViaPfnAndToken(frame.pfn().?, tok);

    return frame.pfn() orelse return error.InvalidPfn;
}

pub fn allocOrder(order: mm.Order, tok: pfmdb.WriteToken) !pfmdb.Pfn {
    if (!order.isValid()) return error.InvalidOrder;

    return allocExactOrder(order, tok) catch |e| switch (e) {
        error.AllocFailed => blk: {
            const higherOrder = order.add(1) orelse return error.AllocFailed;
            const pfn = try allocOrder(higherOrder, tok);
            errdefer freeNoError(pfn, tok);

            try splitFrameAssumeUnused(pfn.frameMut(tok).?, tok);

            // the pfn is already marked as used

            break :blk pfn;
        },
        else => return e,
    };
}

pub fn lockAndAllocOrder(order: mm.Order) !pfmdb.Pfn {
    const tok = pfmdb.lock();
    defer tok.release();

    return allocOrder(order, tok);
}

pub fn markUsedViaPfnAndToken(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken) !void {
    const frame = pfn.frameMut(tok) orelse return error.InvalidPfn;

    assert(frame.getState() == .free);

    markUsed(frame);
}

pub fn getParentOfPfnForOrder(frame: pfmdb.Pfn, order: mm.Order) ?pfmdb.Pfn {
    const buddy = frame.buddyForOrder(order) orelse return null;
    if (buddy.raw() < frame.raw()) return buddy else return frame;
}

pub fn invalidateFrameByPfn(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken) void {
    const frame = pfn.frameMut(tok).?;
    _ = switch (frame.getState()) {
        .free => totalFreePages.fetchSub(frame.info.order.totalPages(), .monotonic),
        .reserved => totalReservedPages.fetchSub(frame.info.order.totalPages(), .monotonic),
        .used => totalUsedPages.fetchSub(frame.info.order.totalPages(), .monotonic),
        else => 0,
    };
    frame.info.active = false;
}

pub inline fn lockAndFree(pfn: pfmdb.Pfn) !void {
    const tok = pfmdb.lock();
    defer tok.release();

    return free(pfn, tok);
}

pub fn free(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken) !void {
    return freeWithMergeLimit(pfn, tok, .unlimited);
}

pub fn freeNoMerge(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken) !void {
    return freeWithMergeLimit(pfn, tok, .nothing);
}

pub fn freeNoError(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken) void {
    return free(pfn, tok) catch |e| {
        log.warn("free from 0x{x} failed with error: {s}", .{ @returnAddress(), @errorName(e) });
    };
}

pub fn freeWithMergeLimit(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken, limit: Limit) !void {
    pfn.assertValid();

    var frame = pfn.frameMut(tok).?;

    frame.info.order.assertValid();
    frame.info.maximum_order.assertValid();

    const min_order = frame.info.order.raw().?;
    if (frame.info.maximum_order != .page) merge: {
        const max_order = (frame.info.maximum_order.raw().?);

        if (min_order >= max_order) break :merge;

        for (min_order..max_order, 1..) |raw_order, i| {
            if (limit == .nothing) break;
            if (limit != .unlimited and i > limit.toInt().?) break;
            const new_order = mm.Order.new(@truncate(raw_order + 1)) orelse break;
            const old_order = mm.Order.new(@truncate(raw_order)) orelse break;

            const buddy = frame.pfn().?.buddyForOrder(old_order).?.frameMut(tok) orelse break;

            if (buddy.getState() != .free) break;

            assert(buddy.info.maximum_order == frame.info.maximum_order);
            assert(buddy.root() == frame.root());
            assert(frame.info.order == old_order);
            assert(buddy.info.order == old_order);

            log.debug("merging PFN {d} and its buddy into one order {d} frame", .{
                frame.pfn().?.raw(),
                new_order.raw().?,
            });

            // get the "parent", e.g. the node that was split (min(frame, buddy)).
            const parent = getParentOfPfnForOrder(
                frame.pfn().?,
                old_order,
            ).?;

            frame = parent.frameMut(tok) orelse break;

            frame.info.order = new_order;

            invalidateFrameByPfn(
                parent.buddyForOrder(old_order).?,
                tok,
            );
        }
    }

    markFreeWithFreelist(frame);
}

pub fn lockAndFreeNoError(pfn: pfmdb.Pfn) void {
    const tok = pfmdb.lock();
    defer tok.release();

    return freeNoError(pfn, tok);
}

fn frameFormFreelistNode(node: *std.DoublyLinkedList.Node, tok: pfmdb.WriteToken) *pfmdb.PageFrame {
    _ = tok;
    return @fieldParentPtr("node", node);
}

pub fn dumpStats(w: *std.Io.Writer) !void {
    const total = bootldr.totalPhysicalPagesWithHoles();
    try w.writeAll("\r\nPHYSICAL FRAME ALLOCATOR STATE:\r\n");
    try w.print("(stats are in 4KiB pages)\r\n", .{});
    try w.print("Total Physical Pages: {d}\r\n", .{total});
    try w.print("Free: {d}/{d}\r\n", .{ totalFreePages.load(.monotonic), total });
    try w.print("Used: {d}/{d}\r\n", .{ totalUsedPages.load(.monotonic), total });
    try w.print("Reserved: {d}/{d}\r\n", .{ totalReservedPages.load(.monotonic), total });
    try w.print("(PFMDB located at 0x{x})\r\n", .{pfmdb.baseAddress()});
}

pub fn init() !void {
    log.info("Initializing Physical Frame Allocator...", .{});

    std.debug.assert(pfmdb.isInitalized());

    const tok = pfmdb.lock();
    errdefer log.err("init failed releasing token...", .{});
    defer tok.release();

    for (bootldr.memory_map(), 0..) |ent, i| {
        log.debug("memory map entry {d}: {s} 0x{x} ({d} pages)", .{
            i,
            @tagName(ent.getType()),
            ent.getPtr(),
            ent.getSizeIn4KiBPages(),
        });

        if (!ent.isFree()) {
            _ = totalReservedPages.fetchAdd(@intCast(ent.getSizeIn4KiBPages()), .monotonic);
            continue;
        }

        std.debug.assert(mm.PAGE_ALIGN.check(ent.getPtr()));

        const base: mm.PhysicalAddr = .{ .raw = ent.getPtr() };

        const newBase, const pages = if (bootmem.startsAt(base.raw)) blk: {
            _, const usedPages = bootmem.disable() orelse @panic("bootmem already disabled");

            assert(usedPages < ent.getSizeIn4KiBPages());

            log.debug("reserving bootmem region ({d} pages)...", .{usedPages});

            // mark bootmem region as reserved
            _ = try initalizeRegionRoots(
                base.typed.pfn,
                usedPages,
                .reserved,
                tok,
                null,
                .static,
            );

            const offBase: usize = @intCast(ent.getPtr() + (usedPages << mm.PAGE_SHIFT));
            const offPages: u32 = @intCast(ent.getSizeIn4KiBPages() - usedPages);

            break :blk .{ mm.PhysicalAddr{ .raw = offBase }, offPages };
        } else .{ base, @as(u32, @intCast(ent.getSizeIn4KiBPages())) };

        // sweep-init region roots for this memory region.
        _ = try initalizeRegionRoots(
            newBase.typed.pfn,
            pages,
            .free,
            tok,
            null,
            .normal,
        );
    }

    // now we have populated the freelist and set up the initale root page frames,
    // we are done with init for now ;)

}

pub const AllocContext = struct {
    map: *const fn (pfn: pfmdb.Pfn) ?[]u8,
    translate: *const fn (addr: usize) ?pfmdb.Pfn,
};

pub fn defaultMapAssumeIdentity(pfn: pfmdb.Pfn) ?[]u8 {
    const addr: mm.PhysicalAddr = .{ .typed = .{ .pfn = pfn } };
    const base: [*]u8 = @ptrFromInt(addr.raw);
    const size = pfn.frame().?.info.order.totalPages() * mm.PAGE_SIZE;
    return base[0..size];
}

pub fn defaultTranslateAssumeIdentity(addr: usize) ?pfmdb.Pfn {
    const paddr: mm.PhysicalAddr = .{ .raw = @intCast(addr) };
    return paddr.typed.pfn;
}

pub fn allocator(context: *const AllocContext) std.mem.Allocator {
    return .{
        .ptr = @ptrCast(@constCast(context)),
        .vtable = &vtable,
    };
}

const vtable = std.mem.Allocator.VTable{
    .alloc = vt_alloc,
    .free = vt_free,
    .resize = vt_resize,
    .remap = std.mem.Allocator.noRemap,
};

fn vt_resize(rawCtx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    _ = ret_addr;

    const context: *const AllocContext = @ptrCast(@alignCast(rawCtx));

    const new_size = alignment.forward(new_len);

    const pfn = (context.translate(@intFromPtr(memory.ptr)) orelse return false);
    const frame = pfn.frame() orelse return false;

    return new_size <= (frame.info.order.totalPages() * mm.PAGE_SIZE);
}

fn vt_alloc(rawCtx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ret_addr;

    const context: *const AllocContext = @ptrCast(@alignCast(rawCtx));

    const size = alignment.forward(len);
    const pages: u32 = @truncate(mm.PAGE_ALIGN.forward(size) >> mm.PAGE_SHIFT);

    const pfn = lockAndAllocAny(pages) catch |e| {
        log.warn("vtable allocation failed with error: {s}", .{@errorName(e)});
        return null;
    };

    return (context.map(pfn) orelse return null).ptr;
}

fn vt_free(rawCtx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = alignment;
    _ = ret_addr;

    const context: *const AllocContext = @ptrCast(@alignCast(rawCtx));

    const pfn = context.translate(@intFromPtr(memory.ptr)) orelse {
        log.warn("vtable free failed to translated address 0x{x}", .{@intFromPtr(memory.ptr)});
        return;
    };

    lockAndFreeNoError(pfn);
}
