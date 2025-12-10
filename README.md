# Zig-Ant-Operating-System (**zAntOS**)

*z*AntOS is a *"rewrite"*(+ major rework is planned) of the [Ant Operating System](http://github.com/ant-os) 
using the zig programming language.

# Requirements
This projects uses `make` for building but a zig install is also required.

*z*AntOS currently uses `BOOTBOOT` as it's bootloader which is compiled from [source](third-party/bootboot).

Currently there are no other third-party deps, but it's likely **zig** will also be added and compiled
from source as well as other libraries.

# Compiling and Running

To compile you have to setup local files and then build `BOOTBOOT` before finally compiling the *z*AntOS Kernel:
```sh 
make setup
make bootboot-loader
make mkbootimg
# cp <prebuild-mkbootimg> devtools/mkbootimg # <-- if using a prebuild mkbootimg binary.
make kernel
```

Then creating a disk image can be done like this:
```sh
make disk
```

*z*AntOS also provided ways of running the generated image, currently only using QEMU+BIOS
but more is planned, to add runners or see how they work or change flags see [`runners.mk`](runners.mk).

Running using QEMU and CDROM Image: 
```sh
make qemu-cd
```

# Stage
This is still **very** early on in development. So... no guarantees it will NOT cause your computer to explode. ;)

# Origin of Template
As it has NOT been modified heavily yet and some of this CODE is from the `bootboot` template,
credit to the author for those unchanged parts of the template.
