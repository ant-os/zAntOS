#include <stdint.h>
#include <stdarg.h>
#include "antk/antk.h"
#include "antk/io.h"
#include "antk/ob.h"

ANTKAPI ANTSTATUS HandleWrite(PIRP Irp, IRP_PARAMS_WRITE *Parameters, void *Context);

ANTKAPI ANTSTATUS AntkDriverEntry(PKO_DRIVER DriverObect, void *unused) {
    AntkDebugPrint("test");

    IoInstallHandler(DriverObect, IRP_MJ_WRITE, HandleWrite);

    return STATUS_SUCCESS;
}

ANTKAPI ANTSTATUS HandleWrite(PIRP Irp, IRP_PARAMS_WRITE *Parameters, void *Context) {
    AntkDebugPrintEx("writing \"%s\" at offset %x", Parameters->Buffer, (int)Parameters->Offset);

    PIRP_STACK_ENTRY StackEntry = IrpCurrentStackEntry(Irp);

    if (StackEntry == NULL) {
        AntkDebugPrint("error: no current stack entry");
        return STATUS_UNKNOWN_ERROR;
    }

    return STATUS_SUCCESS;
}