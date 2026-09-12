/* SPDX-License-Identifier: BSL-1.0 */

/* Questions about a type: its fields, members and methods by name, its
 * attributes, what it holds, and what it comes to. */

#ifndef FLUXION_REFLECT_TYPES_H
#define FLUXION_REFLECT_TYPES_H

#include "descriptors.h"

#ifdef __cplusplus
extern "C" {
#endif

/* NULL when there is none of that name. */
const fxr_field *fxr_type_field(const fxr_type *type, const char *name);
const fxr_member *fxr_type_member(const fxr_type *type, const char *name);
const fxr_method *fxr_type_method(const fxr_type *type, const char *name);
/* An attribute's value, found by the attribute's type. */
const void *fxr_type_attribute(const fxr_type *type, const fxr_type *attribute);
const void *fxr_field_attribute(const fxr_field *field, const fxr_type *attribute);
/* What a pointer, slice, array, vector or optional holds. */
const fxr_type *fxr_type_child(const fxr_type *type);
/* The same type: one descriptor, or the same name, kind and size. */
bool fxr_type_same(const fxr_type *a, const fxr_type *b);
/* fluxion-data's schema fingerprint, and the text it hashes. */
uint64_t fxr_type_fingerprint(const fxr_type *type);
/* Like snprintf: writes what fits with a zero after it, returns the full length. */
size_t fxr_type_describe(const fxr_type *type, char *buffer, size_t capacity);
/* The field, member or method name nearest to `name`, or NULL. */
const char *fxr_type_suggest(const fxr_type *type, const char *name);

#ifdef __cplusplus
}
#endif

#endif
