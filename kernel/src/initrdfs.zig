//! Initrd Filesystem Driver.

const std = @import("std");
const klog = std.log.scoped(.initrdfs_driver);
const driverManager = @import("driverManager.zig");
const callbacks = @import("driverCallbacks.zig");
const filesystem = @import("filesystem.zig");
const ANTSTATUS = @import("types.zig").ANTSTATUS;
const HANDLE = @import("types.zig").HANDLE;
const heap = @import("heap.zig");
const bootboot = @import("bootboot.zig");
const resource = @import("resource.zig");

const DriverObject = driverManager.DriverObject;

fn init(object: *DriverObject) callconv(.c) ANTSTATUS {
    object.setCallback(callbacks.FS_OPEN, &open);
    //object.setCallback(callbacks.FS_CLOSE, &close);
    //  object.setCallback(callbacks.FS_READ, &read);

    klog.debug("Callback handlers have successfully been installed.", .{});

    return .SUCCESS;
}

fn mount(fs: *resource.FilesystemObject) callconv(.c) ANTSTATUS {
    fs.flags.readonly = true;

    return .SUCCESS;
}

fn open(
    _: *const DriverObject,
    fs_handle: *resource.FilesystemObject,
    out_handle: **resource.ResourceDescriptor,
    filename: [*]const u8,
    filename_len: usize,
) callconv(.c) ANTSTATUS {
    _ = out_handle;
    klog.debug("open(\"{s}\") called.", .{filename[0..filename_len]});

    const initrd: [*]u8 = @ptrFromInt(bootboot.bootboot.initrd_ptr);
    var initrd_reader = std.io.Reader.fixed(initrd[0..bootboot.bootboot.initrd_size]);

    const filename_buf = heap.allocator.alloc(u8, filesystem.max_filename_len) catch return .err(.out_of_memory);
    defer heap.allocator.free(filename_buf);

    const linkname_buf = heap.allocator.alloc(u8, filesystem.max_filename_len) catch return .err(.out_of_memory);
    defer heap.allocator.free(linkname_buf);
    var tar_iter = std.tar.Iterator.init(&initrd_reader, .{
        .file_name_buffer = filename_buf,
        .link_name_buffer = linkname_buf,
    });

    var current: std.tar.Iterator.File = undefined;
    var found = false;

    while (true) {
        current = (tar_iter.next() catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => {
                    return ANTSTATUS.err(.general_error);
                },
            }
        }) orelse break;

        if (std.mem.eql(u8, current.name, filename[0..filename_len])) {
            if (current.kind != .file) {
                klog.err("only files are currently supported.", .{});
                return ANTSTATUS.err(.unsupported_operation);
            }

            var file_handle = (resource.keAllocateHandle(.file) catch |e| return .fromZigError(e));
            const file = &file_handle.object.file;
            file.fs_handle = fs_handle;
            file.size = current.size;
            file.flags = .{
                .hidden = false,
                .link = current.kind == .sym_link,
                .readonly = true,
                .system = true,
            };
            // desc.metadata.offset = 0;
            // desc.metadata.name_len = @intCast(current.name.len);
            // var raw_name = &desc.metadata.name;
            // std.mem.copyForwards(u8, raw_name[0..current.name.len], current.name);

            file.private = @ptrCast(initrd[initrd_reader.seek..]);
            found = true;
            break;
        }
    }

    if (!found) {
        return ANTSTATUS.err(.not_found);
    }
    return .SUCCESS;
}

// fn close(
//     _: *const DriverObject,
//     desc: *anyopaque,
// ) callconv(.c) ANTSTATUS {
//     const typed: *FileDescriptor = @ptrCast(@alignCast(desc));

//     klog.debug(
//         "close(<file handle at 0x{x} for file \"{s}\">) called.",
//         .{
//             @intFromPtr(desc),
//             typed.metadata.name[0..typed.metadata.name_len],
//         },
//     );

//     heap.allocator.destroy(typed);

//     return .SUCCESS;
// }

// fn get_fileinfo(
//     _: *const DriverObject,
//     desc: *anyopaque,
//     out_fileinfo: *filesystem.FileInfo,
// ) callconv(.c) ANTSTATUS {
//     const typed: *FileDescriptor = @ptrCast(@alignCast(desc));

//     klog.debug("getfileinfo() called.", .{});

//     out_fileinfo.* = typed.metadata;

//     return .SUCCESS;
// }

// fn read(
//     _: *const DriverObject,
//     desc: *anyopaque,
//     buffer: [*]u8,
//     buffer_size: usize,
// ) callconv(.c) ANTSTATUS {
//     const typed: *FileDescriptor = @ptrCast(@alignCast(desc));

//     if (typed.metadata.offset + buffer_size > typed.metadata.size)
//         return ANTSTATUS.err(.invalid_parameter);

//     const data = typed.data[typed.metadata.offset..(typed.metadata.offset + buffer_size)];
//     @memcpy(buffer[0..buffer_size], data);

//     typed.metadata.offset += buffer_size;

//     return .SUCCESS;
// }
