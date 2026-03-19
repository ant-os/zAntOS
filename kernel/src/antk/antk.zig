const std = @import("std");
const arch = @import("../arch.zig");
const Driver = @import("../io/Driver.zig");

const log = std.log.scoped(.antkapi);

pub const c = @cImport(@cInclude("../include/antk.h"));
const cc = std.builtin.CallingConvention{ .x86_64_sysv = .{} };

const StructField = std.builtin.Type.StructField;

const _KernelSymbolCollection = @import("ksyms.zig")._KernelSymbolCollection;
pub export fn AntkResolveKernelSymbol(sym: [*:0]const u8) linksection(".antk_callbacks") callconv(cc) ?*const anyopaque {
    inline for (@typeInfo(_KernelSymbolCollection).@"struct".fields) |ksym| {
        if (std.mem.eql(
            u8,
            sym[0..std.mem.len(sym)],
            ksym.name,
        )) return @ptrCast(&@field(
            ksym.defaultValue().?,
            ksym.name,
        ));
    }

    return null;
}

comptime {
    @export(&antkDriverEntry, .{ .name = "AntkDriverEntry" });
}
pub export fn antkDriverEntry(driver: *Driver, unused: ?*anyopaque) callconv(arch.cc) u64 {
    if (driver.state != .init) @panic("unexpected driver state");

    const status = driver._entryFn(@ptrCast(driver), unused);

    if (status != 0) {
        driver.state = .poisoned;
        return status;
    }

    driver.state = .loaded;

    return 0;
}

pub export fn AntkDebugPrint(message: [*:0]const u8) callconv(cc) void {
    log.debug("driver: {s}", .{message});
    @breakpoint();
}