//! Interrupts
 
pub inline fn enable() void {
    asm volatile ("sti");
}

pub inline fn disable() void {
    asm volatile ("cli");
}