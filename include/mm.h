#pragma once

#include <stdint.h>
#include <stddef.h>
#include "antk.h"

/// @brief Opaque type representing a virtual memory region.
typedef struct MM_AREA MM_AREA, *PMM_AREA;

typedef uint16_t MM_ALLOC_AREA_FLAGS;
typedef uint64_t MM_MEMORY_TAG;

/// @brief Allocates the requested number of physically continous pages.
/// @param Pages Number of pages.
/// @param OutAddress Output parameter for the physical address of the allocation.
/// @return Any `ANTSTATUS` error-code, `ANTSTATUS_SUCCESS` on success.
ANTKAPI ANTSTATUS MmAllocatePages(
    IN uint32_t Pages,
    OUT size_t* OutAddress
);


/// @brief Frees the requested number of physically continous pages.
/// @param Address Output parameter for the physical address of the allocation.
/// @return Any `ANTSTATUS` error-code, `ANTSTATUS_SUCCESS` on success.
ANTKAPI ANTSTATUS MmFreePages(
    IN size_t Address
);

/// @brief Allocate a virtual memory region
ANTKAPI ANTSTATUS MmAllocateArea(
    IN size_t Size,
    OUT void *Memory,
    IN_OPT size_t MaximumSize,
    IN_OPT MM_ALLOC_AREA_FLAGS Flags,
    IN_OPT MM_MEMORY_TAG Tag,
    OUT_OPT PMM_AREA *Area
);