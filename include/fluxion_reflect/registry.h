/* SPDX-License-Identifier: BSL-1.0 */

/* Types by name, types built from their Zig spelling, and C's own types and
 * functions described to the registry. */

#ifndef FLUXION_REFLECT_REGISTRY_H
#define FLUXION_REFLECT_REGISTRY_H

#include "descriptors.h"

#ifdef __cplusplus
extern "C" {
#endif

fxr_registry *fxr_registry_create(void);
void fxr_registry_destroy(fxr_registry *registry);
fxr_status fxr_registry_add(fxr_registry *registry, const fxr_type *type);
/* A registered type, a primitive ("f32", "uint16_t", "int"), or NULL. */
const fxr_type *fxr_registry_find(const fxr_registry *registry, const char *name);
const fxr_type *fxr_registry_find_id(const fxr_registry *registry, uint64_t id);
/* A type as Zig writes one: "[]const Vec2", "?*Player", "[4]f32". */
fxr_status fxr_registry_resolve(fxr_registry *registry, const char *expression, const fxr_type **out);
size_t fxr_registry_count(const fxr_registry *registry);
const fxr_type *fxr_registry_at(const fxr_registry *registry, size_t index);
const char *fxr_registry_suggest(const fxr_registry *registry, const char *name);

typedef struct fxr_field_desc {
    const char *name;
    const fxr_type *type;
    size_t offset;
} fxr_field_desc;

typedef struct fxr_struct_desc {
    const char *name;
    size_t size;
    size_t alignment;
    const fxr_field_desc *fields;
    size_t field_count;
} fxr_struct_desc;

typedef struct fxr_member_desc {
    const char *name;
    int64_t value;
} fxr_member_desc;

typedef struct fxr_enum_desc {
    const char *name;
    const fxr_type *tag;
    const fxr_member_desc *members;
    size_t member_count;
    bool is_exhaustive;
} fxr_enum_desc;

typedef struct fxr_arm_desc {
    const char *name;
    const fxr_type *type;
} fxr_arm_desc;

typedef struct fxr_union_desc {
    const char *name;
    size_t size;
    size_t alignment;
    const fxr_arm_desc *arms;
    size_t arm_count;
} fxr_union_desc;

typedef struct fxr_function_desc {
    const char *name;
    const fxr_type *const *params;
    size_t param_count;
    const fxr_type *return_type;
    /* Handed to `invoke` as it is: where the function pointer is kept. */
    const void *function;
    fxr_invoke invoke;
} fxr_function_desc;

/* A NULL type anywhere in a description - one looked up under a name the
 * registry does not know - is refused with FXR_UNKNOWN_TYPE. */
fxr_status fxr_registry_define_struct(fxr_registry *registry, const fxr_struct_desc *desc, const fxr_type **out);
fxr_status fxr_registry_define_enum(fxr_registry *registry, const fxr_enum_desc *desc, const fxr_type **out);
fxr_status fxr_registry_define_union(fxr_registry *registry, const fxr_union_desc *desc, const fxr_type **out);
fxr_status fxr_registry_define_function(fxr_registry *registry, const fxr_function_desc *desc, const fxr_method **out);
const fxr_method *fxr_registry_function(const fxr_registry *registry, const char *name);

/* Describing a C struct: the compiler knows the layout, so ask it.
 *
 *     static const fxr_field_desc vec2_fields[] = {
 *         FXR_FIELD(Vec2, x, f32),
 *         FXR_FIELD(Vec2, y, f32),
 *     };
 *     fxr_struct_desc desc = FXR_STRUCT(Vec2, "Vec2", vec2_fields);
 */
#if defined(__cplusplus)
#define FXR_ALIGNOF(T) alignof(T)
#else
#define FXR_ALIGNOF(T) _Alignof(T)
#endif
#define FXR_FIELD(Struct, member, field_type) {#member, (field_type), offsetof(Struct, member)}
#define FXR_STRUCT(Struct, name, fields) {(name), sizeof(Struct), FXR_ALIGNOF(Struct), (fields), sizeof(fields) / sizeof((fields)[0])}

#ifdef __cplusplus
}
#endif

#endif
