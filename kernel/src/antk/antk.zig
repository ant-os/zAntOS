const std = @import("std");
const arch = @import("../arch.zig");
const ANTSTATUS = @import("root").ANTSTATUS;
const Driver = @import("../io/Driver.zig");
const Irp = @import("../io/Irp.zig");

const log = std.log.scoped(.antkapi);

pub const c = @cImport({
    @cInclude("../include/antk.h");
    @cInclude("../include/io.h");
});
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
pub export fn antkDriverEntry(driver: *Driver, unused: ?*anyopaque) callconv(arch.cc) ANTSTATUS {
    if (driver.state != .init) @panic("unexpected driver state");

    const status = driver._entryFn(@ptrCast(driver), unused);

    if (status != c.ANTSTATUS_SUCCESS) {
        driver.state = .poisoned;
        return @enumFromInt(status);
    }

    driver.state = .loaded;

    return .success;
}

pub export fn AntkDebugPrint(message: [*:0]const u8) callconv(cc) void {
    log.debug("driver: {s}", .{message});
    @breakpoint();
}

pub export fn IrpCreate(stack_size: u8, c_outIrp: ?**Irp) ANTSTATUS {
    _ = stack_size; // ignore for now

    if (c_outIrp) |outirp| {
        outirp.* = Irp.create() catch |err| switch (err) {
            error.OutOfMemory => return .out_of_memory,
        };
    } else return .invalid_parameter;

    return .success;
}

pub export fn IoInstallHandler(c_DriverObject: ?*Driver, c_MajorFunc: u8, handler: Driver.Callback) ANTSTATUS{
    const driver = c_DriverObject orelse return .invalid_parameter;
    if (driver.header.@"type" != .driver) return .invalid_parameter;

    const func = std.enums.fromInt(Irp.MajorFunction.Tag, c_MajorFunc) orelse return .invalid_parameter;

    driver.setCallback(func, handler);

    return .success;
}

pub export fn IrpCurrentStackEntry(c_Irp: ?*Irp) ?*Irp.StackEntry {
    return if (c_Irp) |irp| irp.currentEntry() else @panic("invalid parameter");
}