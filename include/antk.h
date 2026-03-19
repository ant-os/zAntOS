/// AntOS Kernel API

#pragma once
#define __C_HEADER_FILE__

#include <stdint.h>

#define IN
#define OUT
#define IN_OPT
#define OUT_OPT
#define ANTKAPI __attribute__((sysv_abi))

typedef struct KO_DRIVER KO_DRIVER, *PKO_DRIVER;

typedef uint64_t ANTSTATUS;
#define ANTSTATUS_SUCCESS ((ANTSTATUS)0)

/// @brief Entrypoint of a AntOS Kernel Mode Driver
/// @param DriverObect The pointer to the driver object
/// @param unused Unused for now
/// @return On error a corresponding `ANTSTATUS` value otherwise `ANTSTATUS_SUCCESS`.
ANTKAPI ANTSTATUS AntkDriverEntry(IN PKO_DRIVER DriverObect, IN void *unused);

/// @brief Prints a debug message
/// @param message The message to print.
/// @return Nothing, errors get ignored.
ANTKAPI void AntkDebugPrint(IN char *message);
