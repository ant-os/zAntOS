# Zig-Ant-Operating-System (**zAntOS**)

*z*AntOS is a *"rewrite"*(+ major rework is planned) of the [Ant Operating System](http://github.com/ant-os) 
using the zig programming language.

# Requirements
This projects uses the `zig` build system for building, so zig installation(see .zigversion` for version) is also required.

*z*AntOS currently uses `antboot2` as it's bootloader which is included in this repository at [source](bootloader).
# Compiling and Running

To compile and run you can use the `./run` script.
```sh 
./run
```
This will build the loader and kernel and run the os using QEMU.

# Stage
This is still **very** early on in development. So... no guarantees it will NOT cause your computer to explode. ;)