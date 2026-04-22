#![no_std]

use core::{cell::UnsafeCell, ffi::c_void, mem::MaybeUninit};

extern crate antos_kernel_sys;


pub struct Object<T>(UnsafeCell<MaybeUninit<T>>);


#[unsafe(no_mangle)]
pub extern "C" fn AntkDriverEntry(driver: antos_kernel_sys::PKO_DRIVER, unused: *const c_void) -> antos_kernel_sys::ANTSTATUS {
    
    unsafe {
        antos_kernel_sys::AntkDebugPrint(c"Hello from the driver".as_ptr().cast_mut());
    }
    return 0;
}

#[unsafe(no_mangle)]
pub extern "C" fn AntkDriverExit(driver: antos_kernel_sys::PKO_DRIVER, unused: *const c_void) -> antos_kernel_sys::ANTSTATUS {
    unsafe {
        antos_kernel_sys::AntkDebugPrint(c"Goodbye from the driver ".as_ptr().cast_mut());
    }
    return 0;
}


#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    unsafe {
        antos_kernel_sys::AntkDebugPrint(c"Driver panicked".as_ptr().cast_mut());
    }
    loop {}
}