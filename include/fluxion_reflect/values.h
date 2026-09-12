/* SPDX-License-Identifier: BSL-1.0 */

/* Values: made, walked into, read, written, compared, and turned into Zig
 * syntax and back. */

#ifndef FLUXION_REFLECT_VALUES_H
#define FLUXION_REFLECT_VALUES_H

#include "descriptors.h"

#ifdef __cplusplus
extern "C" {
#endif

/* A new value on the heap, holding the type's default. */
fxr_status fxr_value_create(const fxr_type *type, fxr_value *out);
void fxr_value_destroy(const fxr_value *value);

fxr_status fxr_value_field(const fxr_value *value, const char *name, fxr_value *out);
fxr_status fxr_value_field_at(const fxr_value *value, size_t index, fxr_value *out);
fxr_status fxr_value_index(const fxr_value *value, size_t index, fxr_value *out);
fxr_status fxr_value_len(const fxr_value *value, size_t *out);
/* "inventory[2].name", "target.?.health", "parent.*.x" */
fxr_status fxr_value_path(const fxr_value *value, const char *path, fxr_value *out);
size_t fxr_value_explain_path(const fxr_value *value, const char *path, char *buffer, size_t capacity);
fxr_status fxr_value_deref(const fxr_value *value, fxr_value *out);

bool fxr_value_is_null(const fxr_value *value);
fxr_status fxr_value_set_null(const fxr_value *value);
/* An optional's or error union's payload: FXR_NULL when there is none. */
fxr_status fxr_value_unwrap(const fxr_value *value, fxr_value *out);
/* The same, first made from its default when there is none. */
fxr_status fxr_value_unwrap_or_init(const fxr_value *value, fxr_value *out);

/* A tagged union's live arm, or NULL. */
const fxr_field *fxr_value_active(const fxr_value *value);
fxr_status fxr_value_activate(const fxr_value *value, const char *arm, fxr_value *payload);

fxr_status fxr_value_get_i64(const fxr_value *value, int64_t *out);
fxr_status fxr_value_get_u64(const fxr_value *value, uint64_t *out);
fxr_status fxr_value_get_f64(const fxr_value *value, double *out);
fxr_status fxr_value_get_bool(const fxr_value *value, bool *out);
/* Lent out: valid while the value holds it. */
fxr_status fxr_value_get_string(const fxr_value *value, fxr_bytes *out);
fxr_status fxr_value_set_i64(const fxr_value *value, int64_t x);
fxr_status fxr_value_set_u64(const fxr_value *value, uint64_t x);
fxr_status fxr_value_set_f64(const fxr_value *value, double x);
fxr_status fxr_value_set_bool(const fxr_value *value, bool x);
/* Into a char array (copied), an enum (a member's name), an error set (an
 * error's name), or a []const u8 - which then points at `text`. */
fxr_status fxr_value_set_string(const fxr_value *value, const char *text, size_t len);
/* Points a [:0]const u8, [*:0]const u8 or [*c]const u8 at `text`. */
fxr_status fxr_value_set_c_string(const fxr_value *value, const char *text);
fxr_status fxr_value_set_error(const fxr_value *value, const char *name);
const char *fxr_value_error_name(const fxr_value *value);

fxr_status fxr_value_copy(const fxr_value *to, const fxr_value *from);
/* Copies, converting between numbers, bools, enums and text. */
fxr_status fxr_value_convert(const fxr_value *to, const fxr_value *from);
bool fxr_value_eql(const fxr_value *a, const fxr_value *b);
uint64_t fxr_value_hash(const fxr_value *value);

/* Zig syntax, as ZON writes it. Like snprintf. */
size_t fxr_value_format(const fxr_value *value, char *buffer, size_t capacity);
/* Reads what fxr_value_format writes; fields left out keep what they held.
 * Strings and slices are allocated from `arena`, which may be NULL. */
fxr_status fxr_value_parse(const fxr_value *value, const char *text, size_t len, fxr_arena *arena);

/* Where strings and slices read in are kept, until it is destroyed. */
fxr_arena *fxr_arena_create(void);
void fxr_arena_destroy(fxr_arena *arena);

#ifdef __cplusplus
}
#endif

#endif
