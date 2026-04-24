#![no_std]

use core::{cell::UnsafeCell, ffi::{CStr, c_void}, mem::MaybeUninit, ptr::{addr_of, addr_of_mut, null, null_mut}};

extern crate antos_kernel_sys;


pub struct Object<T>(UnsafeCell<MaybeUninit<T>>);


#[unsafe(no_mangle)]
pub extern "C" fn AntkDriverEntry(driver: antos_kernel_sys::PKO_DRIVER, unused: *const c_void) -> antos_kernel_sys::ANTSTATUS {
       unsafe {
        antos_kernel_sys::AntkDebugPrint(c"Hello from the driver ".as_ptr());

        let mut mutex = MaybeUninit::uninit();
        let mut attributes = antos_kernel_sys::OBJECT_ATTRIBUTES {
            Size: size_of::<antos_kernel_sys::OBJECT_ATTRIBUTES>(),
            Attributes: 0,
            DirectoryVode: null_mut(),
            Name: null_mut(),
        };

        let mut status;

        status = antos_kernel_sys::ObCreateObject(
            mutex.as_mut_ptr(),
            addr_of_mut!(attributes),
            *antos_kernel_sys::KeMutexType,
            antos_kernel_sys::PROCESSOR_MODE::KernelMode,
            0
        );

        if status != 0 { panic!("failed to create mutex"); }

        antos_kernel_sys::KeInitializeMutex(mutex.assume_init_read());

        antos_kernel_sys::AntkDebugPrintEx(c"mutex: %p".as_ptr(), mutex.assume_init_read());
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