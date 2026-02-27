const std = @import("std");
const toml = @import("toml");
const uefi = std.os.uefi;
const log = std.log.scoped(.antboot2);

var buffer: [0x1000]u8 = undefined;

pub const version_string = "2.0.0-indev";
const ParsedInstallConfig = toml.Parsed(InstallConfig);

pub fn detectOsInstallOnFilesystem(fs: *uefi.protocol.SimpleFileSystem) !?ParsedInstallConfig {
    const root = try fs.openVolume();

    const configfile = root.open(
        std.unicode.utf8ToUtf16LeStringLiteral("ant.toml"),
        .read,
        .{},
    ) catch |e| {
        if (e == error.NotFound) return null;
        return e;
    };

    const infoSize = try configfile.getInfoSize(.file);
    const infoBuf = try uefi.pool_allocator.alignedAlloc(
        u8,
        std.mem.Alignment.of(uefi.protocol.File.Info.File),
        infoSize,
    );
    defer uefi.pool_allocator.free(infoBuf);

    const fileInfo = try configfile.getInfo(.file, infoBuf);

    const fileContents = try uefi.pool_allocator.alloc(u8, fileInfo.file_size);
    defer uefi.pool_allocator.free(fileContents);

    _ = try configfile.read(fileContents);

    var parser = toml.Parser(InstallConfig).init(uefi.pool_allocator);
    defer parser.deinit();

    const config = try parser.parseString(fileContents);

    if (!std.mem.eql(u8, config.value.version, InstallConfig.VERSION)) return error.MismatchedVersion;
    if (!std.mem.eql(u8, config.value.loader.version, version_string)) return error.MismatchedLoaderVersion;

    return config;
}

pub fn getFirstOsInstall() !struct { ParsedInstallConfig, *uefi.protocol.File } {
    const filesystems = try efiBootServices().locateHandleBuffer(.{
        .by_protocol = &uefi.protocol.SimpleFileSystem.guid,
    }) orelse return error.NoFilesystemsFound;

    for (filesystems) |fs_handle| {
        const fs = try efiBootServices().openProtocol(
            uefi.protocol.SimpleFileSystem,
            fs_handle,
            .{ .by_handle_protocol = .{ .agent = uefi.handle } },
        ) orelse continue;
        const config = (detectOsInstallOnFilesystem(fs) catch |e| {
            try efiBootServices().closeProtocol(
                fs_handle,
                uefi.protocol.SimpleFileSystem,
                uefi.handle,
                null,
            );
            log.info("failed to detect install with error: {s}", .{@errorName(e)});
            continue;
        }) orelse {
            try efiBootServices().closeProtocol(
                fs_handle,
                uefi.protocol.SimpleFileSystem,
                uefi.handle,
                null,
            );

            continue;
        };
        return .{ config, try fs.openVolume() };
    }

    return error.NotFound;
}

const InstallConfig = struct {
    pub const VERSION = "0.0.1-antinstall";

    version: []const u8,
    loader: struct {
        name: []const u8,
        version: []const u8,
        verbose: bool,
    },
    system: struct {
        osname: []const u8,
        version: []const u8,
    },
    kernel: struct {
        @"image-path": []const u8,
        parameters: toml.Table,
    },
};

pub fn _logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const chars = std.fmt.bufPrint(
        &buffer,
        "[{s}] {s}: " ++ format ++ "\r\n",
        .{ @tagName(level), @tagName(scope) } ++ args,
    ) catch @panic("buffer to small");

    for (chars) |c| {
        const wide = &[_]u16{ @intCast(c), 0, 0, 0 };
        _ = uefi.system_table.con_out.?.outputString(@ptrCast(wide)) catch unreachable;
    }
}

pub const std_options = std.Options{
    .logFn = _logFn,
    .fmt_max_depth = 3,
};

pub inline fn efiBootServices() *uefi.tables.BootServices {
    return uefi.system_table.boot_services.?;
}

pub fn efiGetFileInfo(
    self: *uefi.protocol.File,
    comptime info: std.meta.Tag(uefi.protocol.File.Info),
    alloc: std.mem.Allocator,
) uefi.Error!struct { *@FieldType(uefi.protocol.File.Info, @tagName(info)), []u8 } {
    const size = try self.getInfoSize(info);
    const buf = alloc.alignedAlloc(
        u8,
        std.mem.Alignment.of(uefi.protocol.File.Info.File),
        size,
    ) catch return error.OutOfResources;
    return .{ try self.getInfo(info, buf), buf };
}

pub fn main() uefi.Error!void {
    const info = try uefi.system_table.boot_services.?.getMemoryMapInfo();
    std.log.info("info = {any}", .{info});

    const config, const volume = getFirstOsInstall() catch |e| {
        log.err("failed to discover os installation: {s}", .{@errorName(e)});
        return uefi.Error.NoMedia;
    };

    log.debug("config = {any}", .{config});

    const volumeLabel = blk: {
        const label, const buf = try efiGetFileInfo(volume, .volume_label, uefi.pool_allocator);
        defer uefi.pool_allocator.free(buf);
        const raw = label.getVolumeLabel();

        break :blk std.unicode.utf16LeToUtf8Alloc(
            uefi.pool_allocator,
            raw[0..std.mem.len(raw)],
        ) catch {
            log.err("non-utf8 volume label", .{});
            return uefi.Error.VolumeCorrupted;
        };
    };
    defer uefi.pool_allocator.free(volumeLabel);
    log.info("Starting {s} (version {s}) from \"{s}\"", .{
        config.value.system.osname,
        config.value.system.version,
        volumeLabel,
    });

    // const mem = uefi.pool_allocator.alignedAlloc(
    //     u8,
    //     .@"8",
    //     (info.len + 1) * info.descriptor_size,
    // ) catch unreachable;

    // const mmap = try uefi.system_table.boot_services.?.getMemoryMap(
    //     mem,
    // );

    //   var mmapiter = mmap.iterator();

    // while (mmapiter.next()) |md| std.log.debug("{any}", .{md});

    // const sfs = (try efiBootServices().locateDevicePath(
    //     uefi.protocol.SimpleFileSystem,
    //     uefizzz
    //     .{},
    // )) orelse {
    //     log.err("unable to locate simple filesystem protocol", .{});
    //     return uefi.Status.not_found;
    // };
    // efiBootServices().closeProtocol(efiBootServices()

    // log.debug("filesystem = {any}", .{sfs});

    // const root = try sfs.openVolume();

    // log.debug("filesystem = {any}", .{sfs});

    while (true) {
        asm volatile ("hlt");
    }
}
