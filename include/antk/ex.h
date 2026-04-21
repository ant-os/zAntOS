#pragma once

#include <stdint.h>
#include <stddef.h>
#include "antk.h"

/// @brief Allocates general-purpose memory from the kernel heap
/// @param Bytes The size of the allocation
/// @param OutMemory Output parameter for the allocated memory.
/// @return Any `ANTSTATUS` error-code, `ANTSTATUS_SUCCESS` on success.
ANTKAPI ANTSTATUS ExAllocateMemory(
    IN size_t Bytes,
    OUT void **OutMemory
);

/// @brief Frees general-purpose memory
/// @param Memory Pointer to the allocated memory.
/// @param Bytes The size of the allocation
/// @return Any `ANTSTATUS` error-code, `ANTSTATUS_SUCCESS` on success.
ANTKAPI ANTSTATUS ExFreeMemory(
    IN void *Memory,
    IN size_t Bytes
);