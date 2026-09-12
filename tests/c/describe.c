/* SPDX-License-Identifier: BSL-1.0 */

/* C describes its own types and a function to the registry, and hands the
 * boss out as a value for the Zig half to read. */

#include "game.h"

Enemy boss = {7, {1.5f, -2.0f}, ENEMY_BOSS, 250, "Grendel", "the Destroyer", {0}};

static int32_t add(int32_t a, int32_t b) { return a + b; }
static int32_t (*const add_pointer)(int32_t, int32_t) = add;

static void add_invoke(const void *function, void *const *args, void *result) {
    int32_t (*const *f)(int32_t, int32_t) = (int32_t (*const *)(int32_t, int32_t))function;
    *(int32_t *)result = (*f)(*(const int32_t *)args[0], *(const int32_t *)args[1]);
}

int fxr_test_c_types(fxr_registry *registry, fxr_value *boss_out) {
    const fxr_type *f32 = fxr_registry_find(registry, "float");
    const fxr_type *u8 = fxr_registry_find(registry, "uint8_t");
    const fxr_type *u32 = fxr_registry_find(registry, "uint32_t");
    const fxr_type *c_int = fxr_registry_find(registry, "int");
    const fxr_type *i32 = fxr_registry_find(registry, "int32_t");
    if (!f32 || !u8 || !u32 || !c_int || !i32) return 1;

    const fxr_field_desc vec2_fields[] = {
        FXR_FIELD(Vec2, x, f32),
        FXR_FIELD(Vec2, y, f32),
    };
    const fxr_struct_desc vec2_desc = FXR_STRUCT(Vec2, "Vec2", vec2_fields);
    const fxr_type *vec2;
    if (fxr_registry_define_struct(registry, &vec2_desc, &vec2) != FXR_OK) return 2;

    const fxr_member_desc kinds[] = {{"slime", ENEMY_SLIME}, {"bat", ENEMY_BAT}, {"boss", ENEMY_BOSS}};
    const fxr_enum_desc kind_desc = {"EnemyKind", c_int, kinds, 3, false};
    const fxr_type *kind;
    if (fxr_registry_define_enum(registry, &kind_desc, &kind) != FXR_OK) return 3;

    const fxr_arm_desc arms[] = {{"whole", i32}, {"fraction", f32}};
    const fxr_union_desc payload_desc = {"Payload", sizeof(Payload), FXR_ALIGNOF(Payload), arms, 2};
    const fxr_type *payload;
    if (fxr_registry_define_union(registry, &payload_desc, &payload) != FXR_OK) return 4;

    /* char[16] holding a zero-terminated name is Zig's [15:0]u8. */
    const fxr_type *name16;
    const fxr_type *c_string;
    if (fxr_registry_resolve(registry, "[15:0]u8", &name16) != FXR_OK) return 5;
    if (fxr_registry_resolve(registry, "[*c]const u8", &c_string) != FXR_OK) return 6;

    const fxr_field_desc enemy_fields[] = {
        FXR_FIELD(Enemy, id, u32),
        FXR_FIELD(Enemy, at, vec2),
        FXR_FIELD(Enemy, kind, kind),
        FXR_FIELD(Enemy, hp, u8),
        FXR_FIELD(Enemy, name, name16),
        FXR_FIELD(Enemy, title, c_string),
        FXR_FIELD(Enemy, payload, payload),
    };
    const fxr_struct_desc enemy_desc = FXR_STRUCT(Enemy, "Enemy", enemy_fields);
    const fxr_type *enemy;
    if (fxr_registry_define_struct(registry, &enemy_desc, &enemy) != FXR_OK) return 7;

    const fxr_type *params[] = {i32, i32};
    const fxr_function_desc add_desc = {"add", params, 2, i32, &add_pointer, add_invoke};
    if (fxr_registry_define_function(registry, &add_desc, 0) != FXR_OK) return 8;

    *boss_out = fxr_value_make(enemy, &boss);
    return 0;
}
