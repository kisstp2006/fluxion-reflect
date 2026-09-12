/* SPDX-License-Identifier: BSL-1.0 */

/* Calling a method, a registered function or a function pointer, with values
 * as arguments. */

#ifndef FLUXION_REFLECT_CALLS_H
#define FLUXION_REFLECT_CALLS_H

#include "descriptors.h"

#ifdef __cplusplus
extern "C" {
#endif

/* `result` may be NULL when what the function returns is not wanted. */
fxr_status fxr_method_call(const fxr_method *method, const fxr_value *args, size_t count, const fxr_value *result);
/* A method of the value's type, with the value as its first argument. */
fxr_status fxr_value_call(const fxr_value *value, const char *method, const fxr_value *args, size_t count, const fxr_value *result);
fxr_status fxr_value_call_pointer(const fxr_value *function_pointer, const fxr_value *args, size_t count, const fxr_value *result);

#ifdef __cplusplus
}
#endif

#endif
