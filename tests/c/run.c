/* SPDX-License-Identifier: BSL-1.0 */

/* The C half of the C API test, which the Zig half calls: every part in
 * turn, each building on what the one before wrote into the hero. `arena`
 * belongs to the caller, since what is read into the hero lives in it and
 * the Zig half still reads it afterwards. */

#include "check.h"

int fxr_test_run(fxr_registry *registry, const fxr_value *hero, fxr_arena *arena, char *report, size_t capacity) {
    check_begin(report, capacity);
    test_types(registry, hero);
    test_values(hero, arena);
    test_calls(registry, hero);
    test_json(hero, arena);
    test_registry(registry);
    return check_failures();
}
