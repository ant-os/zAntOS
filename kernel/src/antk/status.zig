//! AntOS C-Safe Status Code.
// NOTE: Not a source file struct as it needs to be packed.

const std = @import("std");
const capi = @import("antk.zig").c;

comptime {
    if (@sizeOf(ANTSTATUS) != @sizeOf(u64) or @alignOf(ANTSTATUS) != @alignOf(u64))
        @compileError("CRITCIAL: ANTSTATUS is not longer ABI-compatible.");
}

/// ABI-safe status code for errors/etc.
pub const ANTSTATUS = enum(u64) {
    success = capi.ANTSTATUS_SUCCESS,

    pending = capi.ANTSTATUS_PENDING,
    uninit = capi.ANTSTATUS_UNINITIALIZED,


    unknown_error = capi.ANTSTATUS_UNKNOWN_ERROR,
    invalid_parameter = capi.ANTSTATUS_INVALID_PARAMETER,
    unsupported = capi.ANTSTATUS_UNSUPPORTED,
    no_driver = capi.ANTSTATUS_NO_DRIVER,
    out_of_memory = capi.ANTSTATUS_OUT_OF_MEMORY,
    _,
};
