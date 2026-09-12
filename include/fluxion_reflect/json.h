/* SPDX-License-Identifier: BSL-1.0 */

/* Values as JSON, as fluxion-json writes and reads them, or as CBOR. */

#ifndef FLUXION_REFLECT_JSON_H
#define FLUXION_REFLECT_JSON_H

#include "base.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fxr_json_options {
    uint8_t indent;
    bool sort_keys;
    bool skip_defaults;
    bool skip_nulls;
    bool cbor;
} fxr_json_options;

/* `options` may be NULL for compact JSON. Writes what fits into `buffer`,
 * leaving room for a zero after it, and sets `needed` to the full length:
 * give it needed + 1 bytes to have all of it. */
fxr_status fxr_value_to_json(const fxr_value *value, const fxr_json_options *options, char *buffer, size_t capacity, size_t *needed);
/* JSON text, or CBOR, read in as fluxion-json reads it. Strings and slices
 * are allocated from `arena`, which is required. */
fxr_status fxr_value_from_json(const fxr_value *value, const char *text, size_t len, fxr_arena *arena);

#ifdef __cplusplus
}
#endif

#endif
