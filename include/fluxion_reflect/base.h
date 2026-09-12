/* SPDX-License-Identifier: BSL-1.0 */

/* What every other part uses: the ABI version, the handles, text, the status
 * every function returns, and a value. */

#ifndef FLUXION_REFLECT_BASE_H
#define FLUXION_REFLECT_BASE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Bumped whenever a struct in these headers changes. Compare it with
 * fxr_abi_version(). */
#define FXR_ABI_VERSION 1

typedef struct fxr_type fxr_type;
typedef struct fxr_registry fxr_registry;
typedef struct fxr_arena fxr_arena;

/* Text with its length, and a zero after it. */
typedef struct fxr_str {
    const char *ptr;
    size_t len;
} fxr_str;

/* Bytes lent out by a value: not necessarily followed by a zero. */
typedef struct fxr_bytes {
    const char *ptr;
    size_t len;
} fxr_bytes;

typedef enum fxr_status {
    FXR_OK = 0,
    FXR_TYPE_MISMATCH,
    FXR_NO_SUCH_FIELD,
    FXR_NO_SUCH_MEMBER,
    FXR_NO_SUCH_METHOD,
    FXR_NO_SUCH_ERROR,
    FXR_INDEX_OUT_OF_BOUNDS,
    FXR_READ_ONLY,
    FXR_NULL,
    FXR_NOT_ADDRESSABLE,
    FXR_OUT_OF_RANGE,
    FXR_INACTIVE_ARM,
    FXR_NOT_CALLABLE,
    FXR_ARGUMENT_COUNT,
    FXR_ARGUMENT_TYPE,
    FXR_MISSING_SENTINEL,
    FXR_NO_DEFAULT,
    FXR_SYNTAX,
    FXR_OUT_OF_MEMORY,
    FXR_UNSUPPORTED,
    FXR_NAME_TAKEN,
    FXR_INVALID_LAYOUT,
    FXR_UNKNOWN_TYPE
} fxr_status;

/* A place holding a value of a type known at run time. */
typedef struct fxr_value {
    const fxr_type *type;
    void *ptr;
    uint8_t bit_offset;
    bool is_bit_field;
    bool is_const;
} fxr_value;

static inline fxr_value fxr_value_make(const fxr_type *type, void *ptr) {
    fxr_value v = {type, ptr, 0, false, false};
    return v;
}

static inline fxr_value fxr_value_make_const(const fxr_type *type, const void *ptr) {
    fxr_value v = {type, (void *)ptr, 0, false, true};
    return v;
}

uint32_t fxr_abi_version(void);
const char *fxr_status_name(fxr_status status);

#ifdef __cplusplus
}
#endif

#endif
