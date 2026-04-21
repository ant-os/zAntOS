#pragma once

#include <stdint.h>
#include <stddef.h>
#include "antk.h"

typedef struct{
    IN size_t Offset;
    IN size_t BufferLength;
    IN char *Buffer;
} IRP_PARAMS_READ;

typedef struct{
    IN size_t Offset;
    IN size_t BufferLength;
    IN char *Buffer;
} IRP_PARAMS_WRITE;

typedef struct IRP IRP, *PIRP;
typedef struct IRP_STACK_ENTRY IRP_STACK_ENTRY, *PIRP_STACK_ENTRY;

typedef struct KO_DEVICE KO_DEVICE, *PKO_DEVICE;

typedef enum _IRP_MJ_FUNCTION {
    IRP_MJ_READ = 2,
    IRP_MJ_WRITE = 3,
} IRP_MJ_FUNCTION;

typedef ANTSTATUS(*IRP_HANDLER)(IN PIRP Irp, IN void *Parameters, IN_OPT void *Context);

ANTKAPI void IoInstallHandler(IN PKO_DRIVER DriverObject, IN IRP_MJ_FUNCTION MajorFunction, IRP_HANDLER Handler);

ANTKAPI ANTSTATUS IrpCreate(IN uint8_t StackSize, OUT PIRP OutPacket);
ANTKAPI PIRP_STACK_ENTRY IrpCurrentStackEntry(IN PIRP Irp);
ANTKAPI ANTSTATUS IrpAppendEntry(
    IN PIRP Irp,
    IN PKO_DEVICE DeviceObject,
    IN IRP_MJ_FUNCTION MajorFunction, 
    IN void *Parmeters, 
    IN_OPT void *Context, 
    IN_OPT uint8_t Flags
);
ANTKAPI ANTSTATUS IrpDispatch(IN PIRP Irp);
