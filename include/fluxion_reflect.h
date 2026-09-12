/* SPDX-License-Identifier: BSL-1.0 */

/*
 * Fluxion Reflect, from C: the whole API. Each part is a header of its own
 * under fluxion_reflect/, for a file that needs only one of them.
 *
 * The descriptors are the same bytes the Zig side made: every struct is laid
 * out exactly as its Zig counterpart, and the test suite checks that on
 * every target it builds for. Read them directly, or through the functions,
 * which also do what a descriptor cannot say by itself - where a Zig optional
 * keeps its flag, which arm of a union is live.
 *
 * Only <stdbool.h>, <stddef.h> and <stdint.h> are needed, which every
 * compiler has even with no C library, so this works in a browser build.
 */

#ifndef FLUXION_REFLECT_H
#define FLUXION_REFLECT_H

#include "fluxion_reflect/base.h"
#include "fluxion_reflect/descriptors.h"
#include "fluxion_reflect/types.h"
#include "fluxion_reflect/values.h"
#include "fluxion_reflect/calls.h"
#include "fluxion_reflect/json.h"
#include "fluxion_reflect/registry.h"

#endif
