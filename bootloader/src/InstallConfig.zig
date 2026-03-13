pub const VERSION = "0.0.1-antinstall";

pub const Driver = struct {
    @"image-path": []const u8,
};

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
},
driver: []Driver,

