/// PIC
// Source: Osdev Wiki (http://wiki.osdev.org/8259_PIC)

const io = @import("io.zig");

const PIC1: u8 = 0x20;
const PIC2: u8 = 0xA0;
const PIC1_COMMAND: u8 = PIC1;
const PIC1_DATA: u8 = (PIC1 + 1);
const PIC2_COMMAND: u8 = PIC2;
const PIC2_DATA: u8 = (PIC2 + 1);
const ICW1_ICW4: u8 = 0x01;
const ICW1_SINGLE: u8 = 0x02;
const ICW1_INTERVAL4: u8 = 0x04;
const ICW1_LEVEL: u8 = 0x08;
const ICW1_INIT: u8 = 0x10;
const ICW4_8086: u8 = 0x01;
const ICW4_AUTO: u8 = 0x02;
const ICW4_BUF_SLAVE: u8 = 0x08;
const ICW4_BUF_MASTER: u8 = 0x0C;
const ICW4_SFNM: u8 = 0x10;
const CASCADE_IRQ: u8 = 2;


const outb = io.outb;
const inb = io.inb;
inline fn io_wait() void {}

pub fn remapAndDisable() void {
    outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4); // starts the initialization sequence (in cascade mode)
    io_wait();
    outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    io_wait();
    outb(PIC1_DATA, 0x20); // ICW2: Master PIC vector offset
    io_wait();
    outb(PIC2_DATA, 0x28); // ICW2: Slave PIC vector offset
    io_wait();
    outb(PIC1_DATA, 1 << CASCADE_IRQ); // ICW3: tell Master PIC that there is a slave PIC at IRQ2
    io_wait();
    outb(PIC2_DATA, 2); // ICW3: tell Slave PIC its cascade identity (0000 0010)
    io_wait();
    outb(PIC1_DATA, ICW4_8086); // ICW4: have the PICs use 8086 mode (and not 8080 mode)
    io_wait();
    outb(PIC2_DATA, ICW4_8086);
    io_wait();

    outb(PIC1_DATA, 0xff);
    outb(PIC2_DATA, 0xff);
}
