/* SPDX-License-Identifier: BSL-1.0 */

/* The Zig hero, read and written through values.h: paths, numbers, text,
 * bit fields, Zig syntax both ways, copies and comparisons. What this writes,
 * the Zig half checks afterwards. */

#include "check.h"

void test_values(const fxr_value *hero, fxr_arena *arena) {
    fxr_value v;
    uint64_t whole = 0;
    OK(fxr_value_path(hero, "level", &v));
    OK(fxr_value_get_u64(&v, &whole));
    CHECK(whole == 1);
    OK(fxr_value_set_i64(&v, 7));
    CHECK(fxr_value_set_i64(&v, 70000) == FXR_OUT_OF_RANGE);

    double real = 0;
    OK(fxr_value_path(hero, "health", &v));
    OK(fxr_value_set_f64(&v, 42.5));
    OK(fxr_value_get_f64(&v, &real));
    CHECK(real == 42.5);

    fxr_bytes bytes;
    OK(fxr_value_path(hero, "team", &v));
    OK(fxr_value_set_string(&v, "blue", 4));
    OK(fxr_value_get_string(&v, &bytes));
    CHECK(bytes.len == 4 && bytes.ptr[0] == 'b');
    CHECK(fxr_value_set_string(&v, "purple", 6) == FXR_NO_SUCH_MEMBER);

    OK(fxr_value_path(hero, "tags", &v));
    OK(fxr_value_set_string(&v, "xyz", 3));

    OK(fxr_value_path(hero, "flags.flying", &v));
    CHECK(v.is_bit_field);
    OK(fxr_value_set_bool(&v, true));

    OK(fxr_value_path(hero, "inventory.gold", &v));
    OK(fxr_value_set_u64(&v, 99));
    CHECK(fxr_value_path(hero, "inventory.silver", &v) == FXR_NO_SUCH_FIELD);
    CHECK(fxr_value_path(hero, "pal.?.level", &v) == FXR_NULL);

    char buffer[256];
    size_t needed = fxr_value_explain_path(hero, "inventory.gould", buffer, sizeof buffer);
    CHECK(needed > 0 && contains(buffer, "did you mean gold?"));

    const char edit[] = ".{ .name = \"From C\", .inventory = .{ .items = .{ \"rope\", \"lamp\" } } }";
    OK(fxr_value_parse(hero, edit, sizeof edit - 1, arena));
    OK(fxr_value_path(hero, "inventory.items[1]", &v));
    OK(fxr_value_get_string(&v, &bytes));
    CHECK(bytes.len == 4 && bytes.ptr[0] == 'l');
    CHECK(fxr_value_parse(hero, ".{ .name = \"x\" }", 16, 0) == FXR_OUT_OF_MEMORY);

    needed = fxr_value_format(hero, buffer, sizeof buffer);
    CHECK(needed < sizeof buffer);
    CHECK(contains(buffer, ".name = \"From C\""));
    CHECK(contains(buffer, ".level = 7"));
    CHECK(contains(buffer, ".tags = \"xyz\""));
    char tiny[8];
    CHECK(fxr_value_format(hero, tiny, sizeof tiny) == needed && tiny[7] == 0);

    fxr_value copy;
    OK(fxr_value_create(hero->type, &copy));
    CHECK(!fxr_value_eql(&copy, hero));
    OK(fxr_value_copy(&copy, hero));
    CHECK(fxr_value_eql(&copy, hero));
    CHECK(fxr_value_hash(&copy) == fxr_value_hash(hero));
    fxr_value_destroy(&copy);
}
