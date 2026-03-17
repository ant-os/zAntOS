#include <stdint.h>
#include <stdarg.h>

typedef struct KO_DRIVER KO_DRIVER, *PKO_DRIVER;

#define _In_opt_
#define _In_
#define _Out_
#define KAPI

extern void* PsInitialeSystemProcess;

typedef enum ANTSTATUS {
    s = 1,
} ANTSTATUS;

typedef void *PVOID;

__attribute__((sysv_abi)) void AntkDebugPrint(char *message);

__attribute__((sysv_abi)) ANTSTATUS AntkDriverEntry(PKO_DRIVER DriverObect, PVOID unused) {
    AntkDebugPrint("test");
    return 123;
}