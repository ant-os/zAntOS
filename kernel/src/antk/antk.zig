const std = @import("std");
const arch = @import("../hal/arch/arch.zig");
const ANTSTATUS = @import("../antk/status.zig").ANTSTATUS;
const Driver = @import("../io/Driver.zig");
const Device = @import("../io/Driver.zig");
const root = @import("kmod");
const Irp = @import("../io/Irp.zig");
const logger = @import("../debug/logger.zig");
const ob = @import("kmod").ob;
const kmod = @import("kmod");

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
pub const KeMutexType = &root.Mutex.knownObjectType.private;

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

    if (status != c.STATUS_SUCCESS) {
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
    if (c_Object) |obj| {
        _ = ob.unreferenceRaw(obj);
    } else return .invalid_parameter;
    return .success;
}

pub export fn ObReferenceObjectByName(
    c_Path: [*c]const u8,
    c_DesiredAccess: c.ACCESS_MASK,
    c_AccessMode: c.PROCESSOR_MODE,
    c_OutObject: ?**anyopaque,
    c_Type: ?*c.KO_OBJECT_TYPE,
    c_Flags: u32,
    c_RemainingPath: ?*c.ASCII_STRING,
) callconv(cc) ANTSTATUS {
    if (c_OutObject == null) return .invalid_parameter;
    if (c_Path == null) return .invalid_parameter;

    if ((c_Flags & c.OB_VODE_INVALID_FLAGS) != 0) return .invalid_parameter;

    const path = c_Path[0..std.mem.len(c_Path)];

    // we need this to convert from zig slices to our C string type.
    var _zig_remaining_path: []const u8 = undefined;

    c_OutObject.?.* = ob.referenceObjectByName(
        path,
        c_DesiredAccess,
        c_AccessMode == c.KernelMode,
        _zig_validateObjectType(c_Type),
        c_Flags,
        if (c_RemainingPath != null) &_zig_remaining_path else null,
    ) catch return .unknown_error;

    // translate into our C-String type and return STATUS_MORE_PROCESSING_REQUIRED.
    if (c_RemainingPath != null and _zig_remaining_path.len != 0) {
        c_RemainingPath.?.Buffer = @ptrCast(@constCast(_zig_remaining_path.ptr));
        c_RemainingPath.?.Length = _zig_remaining_path.len;
        c_RemainingPath.?.MaximumLength = _zig_remaining_path.len;
        return .more_processing_required;
    }

    return .success;
}

pub export fn KeInitializeMutex(
    c_Mutex: *anyopaque,
) callconv(cc) c.ANTSTATUS {
    const mutex = ob.referenceKnownObject(c_Mutex, kmod.Mutex) catch return c.STATUS_INVALID_PARAMETER;
    defer ob.unreferenceObject(kmod.Mutex, mutex);

    log.debug("mutex::init() on mutex with address 0x{x}!", .{@intFromPtr(mutex)});

    mutex.init();

    return c.STATUS_SUCCESS;
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
        const type_: *ob.Type = _zig_validateObjectType(c_Type) orelse return .invalid_parameter;
        ob.referenceObject(c_Object.?, type_) catch return .invalid_parameter;
    }

    return .success;
}

fn _zig_validateObjectType(
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
    c_OutObject: ?**anyopaque,
    c_ObjectAttributes: c.POBJECT_ATTRIBUTES,
    c_Type: ?*c.KO_OBJECT_TYPE,
    c_ProcessorMode: c.PROCESSOR_MODE,
    c_SizeOverride: usize,
) callconv(cc) c.ANTSTATUS {

    const attrs = (c_ObjectAttributes orelse return c.STATUS_INVALID_PARAMETER).*;
    if (c_OutObject == null) return c.STATUS_INVALID_PARAMETER;

    const type_: *ob.Type = _zig_validateObjectType(c_Type) orelse return c.STATUS_INVALID_PARAMETER;

    const name = if (attrs.Name) |str| str[0..std.mem.len(str)] else null;
    const dir = if (attrs.DirectoryVode != null) (ob.referenceKnownObject(
        @ptrCast(attrs.DirectoryVode.?),
        ob.Vode,
    ) catch return c.STATUS_INVALID_PARAMETER) else null;

    c_OutObject.?.* = ob.createObject(
        anyopaque,
        type_,
        if (c_SizeOverride == 0) null else c_SizeOverride,
        c_ProcessorMode == c.KernelMode,
        dir,
        name,
        attrs.Attributes,
        null,
    ) catch |err| switch (err) {
        // TODO: Translate errors.
        else => {
            log.err("error: {s}", .{@errorName(err)});
            return c.STATUS_UNKNOWN_ERROR;
        },
    };

    return 0;
}

fn _zig_writeOptionalOutParam(comptime T: type, location: ?*T, value: T) void {
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

    _zig_writeOptionalOutParam(u64, c_OutPointerCount, header.ptr_count.load(.monotonic));
    _zig_writeOptionalOutParam(u64, c_OutHandleCount, header.handle_count.load(.monotonic));
    _zig_writeOptionalOutParam(u64, c_OutControlFlags, header.flags.atomic.load(.monotonic));

    return .success;
}
