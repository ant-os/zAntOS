#include <stdint.h>
#include <stdarg.h>
#include "../../include/antk.h"
#include "../../include/io.h"

ANTKAPI ANTSTATUS HandleWrite(PIRP Irp, IRP_PARAMS_WRITE *Parameters, void *Context);

ANTKAPI ANTSTATUS AntkDriverEntry(PKO_DRIVER DriverObect, void *unused) {
    AntkDebugPrint("test");

    IoInstallHandler(DriverObect, IRP_MJ_WRITE, HandleWrite);

    return ANTSTATUS_SUCCESS;
}

ANTKAPI ANTSTATUS HandleWrite(PIRP Irp, IRP_PARAMS_WRITE *Parameters, void *Context) {
    AntkDebugPrintEx("writing \"%s\" at offset %x", Parameters->Buffer, (int)Parameters->Offset);

    PIRP_STACK_ENTRY StackEntry = IrpCurrentStackEntry(Irp);

    if (StackEntry == NULL) {
        AntkDebugPrint("error: no current stack entry");
        return ANTSTATUS_UNKNOWN_ERROR;
    }

    return ANTSTATUS_SUCCESS;
}