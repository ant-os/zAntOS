#pragma once

#include <stdint.h>
#include <stddef.h>
#include "antk.h"

typedef struct KO_OBJECT_TYPE KO_OBJECT_TYPE, *PKO_OBJECT_TYPE;

extern PKO_OBJECT_TYPE *ObObjectType;
extern PKO_OBJECT_TYPE *IoDriverType;
extern PKO_OBJECT_TYPE *IoDeviceType; 
extern PKO_OBJECT_TYPE *PsProcessType; 
extern PKO_OBJECT_TYPE *PsThreadType;

#define ObObjectType  (*ObObjectType)
#define IoDriverType  (*IoDriverType)
#define IoDeviceType  (*IoDeviceType)
#define PsProcessType (*PsProcessType)
#define PsThreadType  (*PsThreadType)

ANTKAPI void ObReferenceObject(IN void *Object);

ANTKAPI ANTSTATUS ObDereferenceObject(IN void *Object);

ANTKAPI ANTSTATUS ObReferenceObjectByPointer(
    IN void *Object,
    IN ACCESS_MASK DesiredAccess,
    IN PROCESSOR_MODE AccessMode,
    IN_OPT PKO_OBJECT_TYPE Type
);

ANTKAPI ANTSTATUS ObCreateObject(
    IN PKO_OBJECT_TYPE Type,
    IN size_t Size,
    IN_OPT char *Name,
    OUT void **OutObject
);


ANTKAPI ANTSTATUS ObQueryObjectInformation(
    IN void *Object,
    OUT_OPT uint64_t *OutPointerCount,
    OUT_OPT uint64_t *OutHandleCount,
    OUT_OPT uint32_t *OutControlFlags
);
