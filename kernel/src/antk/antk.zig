const std = @import("std");
const arch = @import("../hal/arch/arch.zig");
const ANTSTATUS = @import("../antk/status.zig").ANTSTATUS;
const Driver = @import("../io/Driver.zig");
const Device = @import("../io/Driver.zig");
const root = @import("kmod");
const Irp = @import("../io/Irp.zig");
const logger = @import("../debug/logger.zig");
const ob = @import("kmod").ob;


const log = std.log.scoped(.antkapi);

pub const c = @cImport({
    @cInclude("antk/antk.h");
    @cInclude("antk/io.h");
    @cInclude("antk/ob.h");
});
const cc = std.builtin.CallingConvention{ .x86_64_sysv = .{} };

const StructField = std.builtin.Type.StructField;

pub const ObObjectType = &ob.ObObjectType;
pub const IoDriverType = &Driver.knownObjectType.private;
pub const IoDeviceType = &root.Device.knownObjectType.private;
pub const PsProcessType = &root.Process.knownObjectType.private;
pub const PsThreadType = &root.Thread.knownObjectType.private;

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
    logger.println("[debug] DRIVER: {s}", .{message}) catch {};
}

pub export fn AntkDebugPrintEx(format: [*:0]const u8, ...) callconv(cc) void {
    var valist = @cVaStart();
    var index: usize = 0;

    logger.print("[debug] DRIVER: ", .{}) catch {};

    fmt: while (index < std.mem.len(format)) : (index += 1) {
        const chr = format[index];

        switch (chr) {
            '%' => {
                if (index + 1 >= std.mem.len(format)) break :fmt;
                index += 1;
                const spec = format[index];
                (switch (spec) {
                    'd' => logger.writer().printInt(@cVaArg(&valist, u32), 10, .lower, .{}),
                    'x' => logger.writer().printInt(@cVaArg(&valist, c_int), 8, .lower, .{}),
                    'q' => logger.writer().printInt(@cVaArg(&valist, u64), 10, .lower, .{}),
                    'p' => logger.writer().print("0x{x}", .{@cVaArg(&valist, u64)}),
                    's' => logger.writer().print("{s}", .{@cVaArg(&valist, [*:0]const u8)}),
                    else => continue :fmt,
                }) catch {};
            },
            '\n' => {
                logger.newline() catch {};
                logger.print("[debug] DRIVER: ", .{}) catch {};
            },
            else => logger.writer().writeByte(chr) catch {},
        }
    }

    logger.newline() catch {};
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

pub export fn IoInstallHandler(c_DriverObject: ?*anyopaque, c_MajorFunc: u8, handler: Driver.Callback) ANTSTATUS {
    const driver = ob.referenceKnownObject(
        c_DriverObject orelse return .invalid_parameter,
        Driver,
    ) catch return .invalid_parameter;

    defer ob.unreferenceObject(Driver, driver);

    const func = std.enums.fromInt(Irp.MajorFunction.Tag, c_MajorFunc) orelse return .invalid_parameter;

    driver.setCallback(func, handler);

    return .success;
}

pub export fn IrpCurrentStackEntry(c_Irp: ?*Irp) ?*Irp.StackEntry {
    return if (c_Irp) |irp| irp.currentEntry() else @panic("invalid parameter");
}

pub export fn ObReferenceObject(c_Object: ?*anyopaque) callconv(cc) void {
    if (c_Object) |obj| ob.referenceRaw(obj) else {}
}

pub export fn ObDereferenceObject(c_Object: ?*anyopaque) callconv(cc) ANTSTATUS {
    if (c_Object) |obj| ob.unreferenceRaw(obj) else return .invalid_parameter;
    return .success;
}

pub export fn ObReferenceObjectByPointer(
    c_Object: ?*anyopaque,
    c_DesiredAccess: c.ACCESS_MASK,
    c_AccessMode: c.PROCESSOR_MODE,
    c_Type: ?*c.KO_OBJECT_TYPE,
) callconv(cc) ANTSTATUS {
    if (c_Object == null) return .invalid_parameter;
    _ = c_DesiredAccess;
    if (c_AccessMode != c.KernelMode) {
        log.warn("access checking is not implemented", .{});
        return .unsupported;
    }

    if (c_Type == null and c_AccessMode != c.KernelMode)
        return .invalid_parameter;

    if (c_Type == null) ObReferenceObject(c_Object) else {
        const type_: *ob.Type = validateObjectType(c_Type) orelse return .invalid_parameter;
        ob.referenceObject(c_Object.?, type_) catch return .invalid_parameter;
    }

    return .success;
}

fn validateObjectType(
    c_Type: ?*c.KO_OBJECT_TYPE,
) ?*ob.Type {
    if (c_Type == null) return null;
    if (!std.mem.Alignment.of(ob.Type).check(@intFromPtr(c_Type))) return null;
    if (!ob.checkObjectType(
        c_Type.?,
        ob.ObObjectType.?,
    )) return null;

    return @ptrCast(@alignCast(c_Type));
}

pub export fn ObCreateObject(
    c_Type: ?*c.KO_OBJECT_TYPE,
    c_Size: usize,
    c_Name: [*c]const u8,
    c_OutObject: ?**anyopaque,
) callconv(cc) ANTSTATUS {
    if (c_OutObject == null) return .invalid_parameter;

    _ = .{c_Type, c_Name, c_Size};

    // const type_: *ob.Type = validateObjectType(c_Type) orelse return .invalid_parameter;

    // const name = if (c_Name) |str| str[0..std.mem.len(str)] else null;

    // // const object = ob.allocate(anyopaque, type_, c_Size, name) catch |err| switch (err) {
    // //     error.OutOfMemory => return .out_of_memory
    // // };

    // // c_OutObject.?.* = object;

    return .success;
}

fn writeOptionalOutParam(comptime T: type, location: ?*T, value: T) void {
    if (location == null) return;
    location.?.* = value;
}

pub export fn ObQueryObjectInformation(
    c_Object: ?*anyopaque,
    c_OutPointerCount: ?*u64,
    c_OutHandleCount: ?*u64,
    c_OutControlFlags: ?*u64,
) callconv(cc) ANTSTATUS {
    const header = if (c_Object) |obj| ob.getHeader(obj) else return .invalid_parameter;

    writeOptionalOutParam(u64, c_OutPointerCount, header.ptr_count.load(.monotonic));
    writeOptionalOutParam(u64, c_OutHandleCount, header.handle_count.load(.monotonic));
    writeOptionalOutParam(u64, c_OutControlFlags, header.flags.atomic.load(.monotonic));

    return .success;
}
