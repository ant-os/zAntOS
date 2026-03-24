#include <stdint.h>
#include <stdarg.h>
#include "../../include/antk.h"
#include "../../include/io.h"

ANTKAPI ANTSTATUS HandleRead(PIRP Irp, IRP_PARAMS_READ *Parameters, void *Context);

ANTKAPI ANTSTATUS AntkDriverEntry(PKO_DRIVER DriverObect, void *unused) {
    AntkDebugPrint("test");

    IoInstallHandler(DriverObect, IRP_MJ_READ, HandleRead);

    return ANTSTATUS_SUCCESS;
}

ANTKAPI ANTSTATUS HandleRead(PIRP Irp, IRP_PARAMS_READ *Parameters, void *Context) {
    AntkDebugPrint("handling read irp");

    PIRP_STACK_ENTRY StackEntry = IrpCurrentStackEntry(Irp);

    if (StackEntry == NULL) {
        AntkDebugPrint("error: no current stack entry");
        return ANTSTATUS_UNKNOWN_ERROR;
    }

    return ANTSTATUS_SUCCESS;
}