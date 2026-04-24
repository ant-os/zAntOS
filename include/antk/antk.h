/// AntOS Kernel API

#pragma once
#define __C_HEADER_FILE__

#include <stdint.h>
#include <stddef.h>

#define IN
#define OUT
#define IN_OUT
#define IN_OPT
#define OUT_OPT
#define ANTKAPI __attribute__((sysv_abi))

typedef struct KO_DRIVER KO_DRIVER, *PKO_DRIVER;

typedef uint64_t ANTSTATUS;

#define STATUS_SUCCESS (uint64_t)0
#define STATUS_PENDING 0x1000000000000
#define STATUS_UNINITIALIZED 0x1000000000001
#define STATUS_UNKNOWN_ERROR 0x8000000000000
#define STATUS_INVALID_PARAMETER 0x8000000000001
#define STATUS_UNSUPPORTED 0x8000000000002
#define STATUS_NO_DRIVER 0x8000000000003
#define STATUS_OUT_OF_MEMORY 0x8000000000004
#define STATUS_NO_ASSOCIATED_OBJECT 0x8000000000005
#define STATUS_TYPE_MISMATCH 0x8000000000006
#define STATUS_INVALID_PATH 0x8000000000007
#define STATUS_MORE_PROCESSING_REQUIRED 0x8000000000008
#define STATUS_MORE_PROCESSING_REQUIRED 0x8000000000008




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

/// @brief A unmanaged ascii string with the given length, buffer and maximum length.
typedef struct {
    /// @brief The backing buffer of the string.
    /// @warning There is no gurantee this buffer is `NULL`-terminated.
    /// @note NULL: If `Buffer` is null then the string should ALWAYS be considered empty.
    char  *Buffer;
    /// @brief the lenght of the string.
    /// @invariant must be less or equal to `MaximumLength`.
    size_t Length;
    /// @brief the lenght capacity of the string.
    /// @invariant must not overflow the backing buffer.
    size_t MaximumLength;
} ASCII_STRING, *PASCII_STRING;
