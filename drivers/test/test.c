#include <stdint.h>
#include <stdarg.h>
#include "../../include/antk.h"

ANTKAPI ANTSTATUS AntkDriverEntry(PKO_DRIVER DriverObect, void *unused) {
    AntkDebugPrint("test");
    return ANTSTATUS_SUCCESS;
}