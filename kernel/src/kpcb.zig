//! Kernel Processor Control Block
//!
//! All fields defined in this file-level struct are per cpu core
//! and can be accessed via .local for the current cpu core.
//! 

const std = @import("std");
const bootmem = @import("bootmem.zig");
const arch = @import("arch.zig");
const builtin = @import("builtin");

const KPCB = @This();

pub const CANARY: u32 = @truncate(0x4B41504341459);

// PER CPU STATE //

canary: u32 = CANARY,
testdummy: if (builtin.is_test) u32 else void,

// END PER CPU STATE //

var cpu_cores: [arch.MAX_SUPPORTED_CORES]?*KPCB = .{null} ** arch.MAX_SUPPORTED_CORES;
pub const local: (*allowzero addrspace(.gs) KPCB) = @ptrFromInt(0x0);
pub var bsp: *KPCB = undefined;

pub inline fn current() *KPCB {
    return cpu_cores[arch.current_cpu()] orelse @panic("core not initalized");
}

pub noinline fn early_init() !void {
    const log = std.log.scoped(.processor_init);

    std.debug.assert(arch.current_cpu() == arch.bspid());
    std.debug.assert(cpu_cores[arch.bspid()] == null);

    // we hard-limit the number of cpu cores to a hard cap for simplicity, 
    // this is fine during VM-testing but should be reworked before first stable release.
    if (arch.numcores() > arch.MAX_SUPPORTED_CORES){
       log.err("Only {} or less CPU cores supported but system has {} cores!", .{
        arch.MAX_SUPPORTED_CORES,
        arch.numcores()
       }); 

       arch.halt_cpu();
    }

    bsp = try bootmem.allocator.create(KPCB);

    bsp.* = std.mem.zeroInit(KPCB, .{});

    cpu_cores[arch.bspid()] = bsp;

    arch.Msr.write(.gs_base, @intFromPtr(bsp));
    arch.Msr.write(.kernel_gs_base, @intFromPtr(bsp));
    
    log.info(
        "KPCB for BSP initalized using base 0x{x}.",
        .{@intFromPtr(bsp)},
    );
}

const ktest = @import("ktest.zig");

test "local update" {
    local.testdummy = 0xdeadbeef;

    const value = cpu_cores[arch.current_cpu()].?.testdummy;

    try ktest.expectEqual(value, 0xdeadbeef);
    try ktest.expectEqual(local.testdummy, value);
}

test current {
    try ktest.expectEqual(current().canary, CANARY);
}

test "fsbase" {
    const addr = @intFromPtr(current());
    try ktest.expectEqual(arch.Msr.read(.gs_base), addr);
    try ktest.expectEqual(arch.Msr.read(.kernel_gs_base), addr);
}

comptime { std.testing.refAllDecls(@This()); }