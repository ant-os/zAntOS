#pragma once

#include <stdint.h>
#include <stddef.h>
#include "antk.h"

// /// @brief Opaque type representing a virtual memory region.
// typedef struct MM_AREA MM_AREA, *PMM_AREA;

// typedef uint16_t MM_ALLOC_AREA_FLAGS;
// typedef uint64_t MM_MEMORY_TAG;

// /// @brief Allocates the requested number of physically continous pages.
// /// @param Pages Number of pages.
// /// @param OutAddress Output parameter for the physical address of the allocation.
// /// @return Any `ANTSTATUS` error-code, `ANTSTATUS_SUCCESS` on success.
// ANTKAPI ANTSTATUS MmAllocatePages(
//     IN uint32_t Pages,
//     OUT size_t* OutAddress
// );

// ANTKAPI ANTSTATUS MmModifyPhysicalMemory(
//     IN size_t Address,
//     IN size_t NumberOfBytes,
//     IN uint8_t Operation,
//     IN_OPT void* Buffer,
//     IN_OPT uint8_t Flags
// );

// /// @brief Frees the requested number of physically continous pages.
// /// @param Address Output parameter for the physical address of the allocation.
// /// @return Any `ANTSTATUS` error-code, `ANTSTATUS_SUCCESS` on success.
// ANTKAPI ANTSTATUS MmFreePages(
//     IN size_t Address
// );

// #define _VALUE(ty, v) ((ty)(v))
// #define MM_AREA_NONPAGED _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 8)
// #define MM_AREA_LAZY _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 9)
// #define MM_AREA_USER _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 2)
// #define MM_AREA_WRITABLE _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 0)
// #define MM_AREA_ZEROPAGE _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 10)
// #define MM_AREA_SHARED _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 11)
// #define MM_AREA_AQUIRE_EXCLUSIVE _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 12)
// #define MM_AREA_TEMPORARY _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 13)
// #define MM_AREA_GUARD_END _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 14)
// #define MM_AREA_GUARD_START _VALUE(MM_ALLOC_AREA_FLAGS, 1 << 15)

// /// @brief Allocate a virtual memory region
// ANTKAPI ANTSTATUS MmAllocateArea(
//     IN size_t Size,
//     OUT void *Memory,
//     IN_OPT size_t MaximumSize,
//     IN_OPT MM_ALLOC_AREA_FLAGS Flags,
//     IN_OPT MM_MEMORY_TAG Tag,
//     OUT_OPT PMM_AREA *Area
// );


