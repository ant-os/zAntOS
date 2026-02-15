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

fn initPageFrame(
    frame: *pfmdb.PageFrame,
    base: usize,
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
        "initalizing {s} page frame at PFN {d} with order {any}(max {any}), origin frame of {any}, tagged {s} and physical base of 0x{x}",
        .{ if (root) "root" else "leaf", frame.pfn().?.raw(), order.raw(), max_order.raw(), origin.raw(), @tagName(tag), base },
    );

    std.debug.assert(std.mem.isAligned(base, mm.PAGE_SIZE));

    frame.* = .{
        .info = .{
            .flat_pfn = @intCast(base / mm.PAGE_SIZE),
            .tag = tag,
            .order = order,
            .maximum_order = max_order,
            .flags = .{ .root = root },
        },
        .origin = origin,
        .state = .not_present,
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
    std.debug.assert(frame.state != .not_present);

    const order = frame.info.order.sub(1) orelse return error.PageFrame;
    const buddy = getBuddyOfPfnForOrder(frame.pfn().?, order) orelse return error.NoBuddyFrameFound;

    frame.info.order = order;
    const bfp = buddy.frameMut(tok).?;

    try initPageFrame(
        bfp,
        (frame.info.flat_pfn + order.totalPages()) * mm.PAGE_SIZE,
        order,
        .normal,
        frame.root(),
        false,
    );

    markFreeWithFreelist(bfp);
}

inline fn markFreeWithFreelist(frame: *pfmdb.PageFrame) void {
    frame.state = .{ .free = .{} };
    getGlobalFreelistForOrder(frame.info.order).?.append(&frame.state.free);
}

fn initalizeRegionRoots(
    origin: pfmdb.Pfn,
    pages: u32,
    base: usize,
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
        "initalizing {s} root page frame at PFN {d}, order {any}, tagged {s} with physical base of 0x{x}",
        .{ @tagName(state), frame.pfn().?.raw(), order.raw(), @tagName(kind), base },
    );

    try initPageFrame(
        frame,
        base,
        order,
        kind,
        upper_region orelse .invalid,
        true,
    );

    switch (state) {
        .reserved => frame.state = .reserved,
        .used => frame.state = .{ .used = .{} },
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
        base + (order.totalPages() * mm.PAGE_SIZE),
        state,
        tok,
        upper_region,
        kind,
    ) + order.totalPages() else order.totalPages();
}

pub fn allocExactOrder(order: mm.Order, tok: pfmdb.WriteToken) !pfmdb.Pfn {
    if (!order.isValid()) return error.InvalidOrder;

    const freelist = getGlobalFreelistForOrder(order).?;

    const frame = frameFormFreelistNode(freelist.pop() orelse return error.AllocFailed, tok);

    std.debug.assert(frame.state == .free);
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

    assert(frame.state == .free);

    frame.state = .{ .used = .{ .refcount = 1 } };
}

pub fn getParentOfPfnForOrder(frame: pfmdb.Pfn, order: mm.Order) ?pfmdb.Pfn {
    const buddy = frame.buddyForOrder(order) orelse return null;
    if (buddy.raw() < frame.raw()) return buddy else return frame;
}

pub fn invalidateFrameByPfn(pfn: pfmdb.Pfn, tok: pfmdb.WriteToken) void {
    const frame = pfn.frameMut(tok).?;
    frame.state = .not_present;
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

            if (buddy.state != .free) break;

            assert(buddy.info.maximum_order == frame.info.maximum_order);
            assert(buddy.state != .not_present);
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
    const state: *pfmdb.PageFrame.State = @fieldParentPtr("free", node);
    return @fieldParentPtr("state", state);
}

pub fn init() !void {

    log.info("Initializing Physical Frame Allocator...", .{});

    std.debug.assert(pfmdb.isInitalized());

    const tok = pfmdb.lock();
    errdefer log.err("init failed releasing token...", .{});
    defer tok.release();

    var region_offset: u32 = 0;

    for (bootldr.memory_map(), 0..) |ent, i| {
        log.debug("memory map entry {d}: {s} 0x{x} ({d} pages)", .{
            i,
            @tagName(ent.getType()),
            ent.getPtr(),
            ent.getSizeIn4KiBPages(),
        });

        if (!ent.isFree()) continue;

        std.debug.assert(mm.PAGE_ALIGN.check(ent.getPtr()));

        const base, const pages = if (bootmem.managesPointer(ent.getPtr())) blk: {
            const base, const usedPages = bootmem.disable() orelse @panic("bootmem already disabled");

            assert(usedPages < ent.getSizeIn4KiBPages());

            const bootmemPfn = pfmdb.Pfn.new(region_offset).?;

            log.debug("reserving bootmem region ({d} pages)...", .{usedPages});

            // mark bootmem region as reserved
            region_offset += try initalizeRegionRoots(
                bootmemPfn,
                usedPages,
                base,
                .reserved,
                tok,
                null,
                .static,
            );

            const newBase: usize = @intCast(ent.getPtr() + (usedPages << mm.PAGE_SHIFT));
            const newPages: u32 = @intCast(ent.getSizeIn4KiBPages() - usedPages);

            break :blk .{ newBase, newPages };
        } else .{ @as(usize, @intCast(ent.getPtr())), @as(u32, @intCast(ent.getSizeIn4KiBPages())) };

        // sweep-init region roots for this memory region.
        region_offset += try initalizeRegionRoots(
            pfmdb.Pfn.new(region_offset).?,
            pages,
            base,
            .free,
            tok,
            null,
            .normal,
        );
    }

    // now we have populated the freelist and set up the initale root page frames,
    // we are done with init for now ;)

}
