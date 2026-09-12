/* SPDX-License-Identifier: BSL-1.0 */

/* Zig methods called from C through calls.h, with arguments converted on
 * the way in and the result on the way out, and a C function registered by
 * describe.c called the same way. */

#include "check.h"

void test_calls(const fxr_registry *registry, const fxr_value *hero) {
    double amount = 8;
    float healed = 0;
    const fxr_value args[] = {fxr_value_make(fxr_registry_find(registry, "f64"), &amount)};
    const fxr_value healed_value = fxr_value_make(fxr_registry_find(registry, "f32"), &healed);
    OK(fxr_value_call(hero, "heal", args, 1, &healed_value));
    CHECK(healed == 50.5f);
    CHECK(fxr_value_call(hero, "hurt", args, 1, 0) == FXR_NO_SUCH_METHOD);

    const fxr_method *greet = fxr_type_method(hero->type, "greet");
    CHECK(greet != 0);
    if (greet) {
        uint8_t times = 3;
        uint32_t greeting = 0;
        const fxr_value greet_args[] = {*hero, fxr_value_make(fxr_registry_find(registry, "u8"), &times)};
        const fxr_value greeting_value = fxr_value_make(fxr_registry_find(registry, "u32"), &greeting);
        OK(fxr_method_call(greet, greet_args, 2, &greeting_value));
        CHECK(greeting == 21);
    }

    const fxr_method *sum = fxr_registry_function(registry, "add");
    CHECK(sum != 0);
    if (sum) {
        int32_t a = 40, b = 2, c = 0;
        const fxr_type *i32 = fxr_registry_find(registry, "int32_t");
        const fxr_value sum_args[] = {fxr_value_make(i32, &a), fxr_value_make(i32, &b)};
        const fxr_value sum_result = fxr_value_make(i32, &c);
        OK(fxr_method_call(sum, sum_args, 2, &sum_result));
        CHECK(c == 42);
    }
}
