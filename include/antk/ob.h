#pragma once

#include <stdint.h>
#include <stddef.h>
#include "antk.h"

typedef struct KO_OBJECT_TYPE KO_OBJECT_TYPE, *PKO_OBJECT_TYPE;
typedef struct KO_VODE KO_VODE, *PKO_VODE;

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

typedef struct 
{
    size_t Size;
    PKO_VODE DirectoryVode;
    char * Name;
    uint32_t Attributes;
} OBJECT_ATTRIBUTES, POBJECT_ATTRIBUTES;

ANTKAPI void ObReferenceObject(IN void *Object);

ANTKAPI ANTSTATUS ObDereferenceObject(IN void *Object);

ANTKAPI ANTSTATUS ObReferenceObjectByPointer(
    IN void *Object,
    IN ACCESS_MASK DesiredAccess,
    IN PROCESSOR_MODE AccessMode,
    IN_OPT PKO_OBJECT_TYPE Type
);

ANTKAPI ANTSTATUS ObCreateObject(
    OUT void **OutObject,
    IN POBJECT_ATTRIBUTES ObjectAttributes,
    IN PKO_OBJECT_TYPE Type,
    IN PROCESSOR_MODE AccessMode,
    IN_OPT size_t Size
);


ANTKAPI ANTSTATUS ObQueryObjectInformation(
    IN void *Object,
    OUT_OPT uint64_t *OutPointerCount,
    OUT_OPT uint64_t *OutHandleCount,
    OUT_OPT uint32_t *OutControlFlags
);


#define OB_VODE_NOFOLLOW (0x1 << 1)
#define OB_VODE_NOSHADOW (0x1 << 2)
#define OB_VODE_OPEN (0x1 << 16)


// ObReferenceObjectByName("//Device/Null", GENERIC_READ | GENERIC_WRITE, KernelMode, &Root, ObVodeType, OB_VODE_OPEN);
ANTKAPI ANTSTATUS ObReferenceObjectByName(
    IN char *Path,
    IN ACCESS_MASK DesiredAccess,
    IN PROCESSOR_MODE AccessMode,
    OUT void **OutObject,
    IN_OPT PKO_OBJECT_TYPE Type,
    IN_OPT uint32_t Flags
);