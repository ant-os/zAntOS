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
    success =                   capi.STATUS_SUCCESS,
    pending =                   capi.STATUS_PENDING,
    uninit =                    capi.STATUS_UNINITIALIZED,
    unknown_error =             capi.STATUS_UNKNOWN_ERROR,
    invalid_parameter =         capi.STATUS_INVALID_PARAMETER,
    unsupported =               capi.STATUS_UNSUPPORTED,
    no_driver =                 capi.STATUS_NO_DRIVER,
    out_of_memory =             capi.STATUS_OUT_OF_MEMORY,
    more_processing_required =  capi.STATUS_MORE_PROCESSING_REQUIRED,
};
