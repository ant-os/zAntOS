/// AntOS Kernel API

#pragma once
#define __C_HEADER_FILE__

#include <stdint.h>

#define IN
#define OUT
#define IN_OUT
#define IN_OPT
#define OUT_OPT
#define ANTKAPI __attribute__((sysv_abi))

typedef struct KO_DRIVER KO_DRIVER, *PKO_DRIVER;

typedef uint64_t ANTSTATUS;

#define ANTSTATUS_SUCCESS (uint64_t)0
#define ANTSTATUS_PENDING 0x1000000000000
#define ANTSTATUS_UNINITIALIZED 0x1000000000001
#define ANTSTATUS_UNKNOWN_ERROR 0x8000000000000
#define ANTSTATUS_INVALID_PARAMETER 0x8000000000001
#define ANTSTATUS_UNSUPPORTED 0x8000000000002
#define ANTSTATUS_NO_DRIVER 0x8000000000003
#define ANTSTATUS_OUT_OF_MEMORY 0x8000000000004

typedef enum _PROCESSOR_MODE {
    UserMode = 1,
    KernelMode = 0,
} PROCESSOR_MODE;

typedef uint64_t ACCESS_MASK;


/// @brief Entrypoint of a AntOS Kernel Mode Driver
/// @param DriverObect The pointer to the driver object
/// @param unused Unused for now
/// @return On error a corresponding `ANTSTATUS` value otherwise `ANTSTATUS_SUCCESS`.
ANTKAPI ANTSTATUS AntkDriverEntry(IN PKO_DRIVER DriverObect, IN void *unused);

/// @brief Prints a debug message
/// @param message The message to print.
/// @return Nothing, errors get ignored.
ANTKAPI void AntkDebugPrint(IN char *message);

/// @brief Prints a formatted debug message
/// @param message The message to print.
/// @param ... Format Args
/// @return Nothing, errors get ignored.
ANTKAPI void AntkDebugPrintEx(IN char *message, ...);