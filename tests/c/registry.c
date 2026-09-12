/* SPDX-License-Identifier: BSL-1.0 */

/* The registry from C: a description with a misspelt type refused, and the
 * C types describe.c registered, read and written back through it. */

#include "check.h"
#include "game.h"

void test_registry(fxr_registry *registry) {
    const fxr_field_desc misspelt[] = {{"x", fxr_registry_find(registry, "flaot"), 0}};
    const fxr_struct_desc bad = {"Bad", 4, 4, misspelt, 1};
    CHECK(fxr_registry_define_struct(registry, &bad, 0) == FXR_UNKNOWN_TYPE);
    CHECK(fxr_registry_add(registry, 0) == FXR_UNKNOWN_TYPE);
    CHECK(fxr_registry_find(registry, "Bad") == 0);

    fxr_value enemy = fxr_value_make(fxr_registry_find(registry, "Enemy"), &boss);
    CHECK(enemy.type != 0);
    if (!enemy.type) return;
    fxr_value v;
    fxr_bytes bytes;
    OK(fxr_value_path(&enemy, "at.y", &v));
    OK(fxr_value_set_f64(&v, 3.25));
    CHECK(boss.at.y == 3.25f);
    OK(fxr_value_path(&enemy, "kind", &v));
    OK(fxr_value_get_string(&v, &bytes));
    CHECK(bytes.len == 4 && bytes.ptr[0] == 'b');
    OK(fxr_value_set_string(&v, "bat", 3));
    CHECK(boss.kind == ENEMY_BAT);
    OK(fxr_value_set_i64(&v, 99));
    CHECK(boss.kind == 99);
    OK(fxr_value_path(&enemy, "title", &v));
    OK(fxr_value_get_string(&v, &bytes));
    CHECK(same_text(bytes.ptr, bytes.len, "the Destroyer"));
    OK(fxr_value_path(&enemy, "payload.fraction", &v));
    OK(fxr_value_set_f64(&v, 0.5));
    CHECK(boss.payload.fraction == 0.5f);
    boss.kind = ENEMY_BOSS;
}
