#include <stdint.h>
#include <stdarg.h>

typedef struct KO_DRIVER KO_DRIVER, *PKO_DRIVER;

#define _In_opt_
#define _In_
#define _Out_
#define KAPI

typedef enum ANTSTATUS {
    s = 1,
} ANTSTATUS;

typedef void *PVOID;

ANTSTATUS DriverLoad(PKO_DRIVER DriverObect, PVOID unused) {
    DbgWriteLine("test");
    return 123;
}