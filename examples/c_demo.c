/* SPDX-License-Identifier: BSL-1.0 */

/* A C program with no Zig in it: it describes its own structs to a registry,
 * then reads, writes, prints, serialises and calls through it.
 * Run it with `zig build example-c`. */

#include <stdio.h>
#include <string.h>

#include "fluxion_reflect.h"

typedef struct Vec2 {
    float x;
    float y;
} Vec2;

enum { KIND_SLIME, KIND_BAT, KIND_DRAGON };

typedef struct Monster {
    char name[16];
    int kind;
    Vec2 at;
    uint16_t hp;
    float speed;
} Monster;

static float reach(Vec2 at, float speed) { return at.x * at.x + at.y * at.y + speed * speed; }
static float (*const reach_pointer)(Vec2, float) = reach;

static void reach_invoke(const void *function, void *const *args, void *result) {
    float (*const *f)(Vec2, float) = (float (*const *)(Vec2, float))function;
    *(float *)result = (*f)(*(const Vec2 *)args[0], *(const float *)args[1]);
}

static const char *status(fxr_status s) { return fxr_status_name(s); }

int main(void) {
    fxr_registry *registry = fxr_registry_create();
    const fxr_type *f32 = fxr_registry_find(registry, "float");
    const fxr_type *u16 = fxr_registry_find(registry, "uint16_t");
    const fxr_type *c_int = fxr_registry_find(registry, "int");
    const fxr_type *name16;
    /* char[16] holding a zero-terminated name is Zig's [15:0]u8: fifteen bytes and the zero. */
    fxr_registry_resolve(registry, "[15:0]u8", &name16);

    const fxr_field_desc vec2_fields[] = {FXR_FIELD(Vec2, x, f32), FXR_FIELD(Vec2, y, f32)};
    const fxr_struct_desc vec2_desc = FXR_STRUCT(Vec2, "Vec2", vec2_fields);
    const fxr_type *vec2;
    fxr_registry_define_struct(registry, &vec2_desc, &vec2);

    const fxr_member_desc kinds[] = {{"slime", KIND_SLIME}, {"bat", KIND_BAT}, {"dragon", KIND_DRAGON}};
    const fxr_enum_desc kind_desc = {"Kind", c_int, kinds, 3, false};
    const fxr_type *kind;
    fxr_registry_define_enum(registry, &kind_desc, &kind);

    const fxr_field_desc monster_fields[] = {
        FXR_FIELD(Monster, name, name16), FXR_FIELD(Monster, kind, kind), FXR_FIELD(Monster, at, vec2),
        FXR_FIELD(Monster, hp, u16),      FXR_FIELD(Monster, speed, f32),
    };
    const fxr_struct_desc monster_desc = FXR_STRUCT(Monster, "Monster", monster_fields);
    const fxr_type *monster;
    fxr_registry_define_struct(registry, &monster_desc, &monster);

    const fxr_type *params[] = {vec2, f32};
    const fxr_function_desc reach_desc = {"reach", params, 2, f32, &reach_pointer, reach_invoke};
    fxr_registry_define_function(registry, &reach_desc, 0);

    printf("--- the types this program described ---\n");
    for (size_t i = 0; i < fxr_registry_count(registry); i++) {
        const fxr_type *t = fxr_registry_at(registry, i);
        printf("%s (%s, %zu bytes)\n", t->name.ptr, fxr_kind_name(t->kind), t->size);
        if (t->kind != FXR_STRUCT) continue;
        for (size_t f = 0; f < t->info.structure.fields.len; f++) {
            const fxr_field *field = &t->info.structure.fields.ptr[f];
            printf("  %s: %s at %zu\n", field->name.ptr, field->type->name.ptr, field->offset);
        }
    }

    printf("\n--- written by name ---\n");
    Monster m = {0};
    fxr_value v = fxr_value_make(monster, &m);
    fxr_value field;
    fxr_value_field(&v, "name", &field);
    fxr_value_set_string(&field, "Smaug", 5);
    fxr_value_path(&v, "at.x", &field);
    fxr_value_set_f64(&field, 1.5);
    fxr_value_field(&v, "kind", &field);
    fxr_value_set_string(&field, "bat", 3);
    printf("C sees: name=%s kind=%d at.x=%g\n", m.name, m.kind, (double)m.at.x);

    char text[256];
    fxr_arena *arena = fxr_arena_create();
    const char edit[] = ".{ .kind = .dragon, .at = .{ .x = 3, .y = 4 }, .hp = 900, .speed = 2 }";
    printf("parse: %s\n", status(fxr_value_parse(&v, edit, sizeof edit - 1, arena)));
    fxr_value_format(&v, text, sizeof text);
    printf("%s\n", text);

    fxr_value_field(&v, "hp", &field);
    printf("hp = 70000: %s\n", status(fxr_value_set_i64(&field, 70000)));
    fxr_value_explain_path(&v, "at.z", text, sizeof text);
    printf("at.z: %s\n", text);

    printf("\n--- JSON, and back ---\n");
    char json[256];
    size_t needed = 0;
    const fxr_json_options pretty = {2, false, false, false, false};
    fxr_value_to_json(&v, &pretty, json, sizeof json, &needed);
    printf("%s\n", json);
    Monster copy = {0};
    fxr_value copy_value = fxr_value_make(monster, &copy);
    printf("read back: %s, the same: %s\n", status(fxr_value_from_json(&copy_value, json, needed, arena)),
           fxr_value_eql(&copy_value, &v) ? "yes" : "no");

    printf("\n--- a C function, called by name ---\n");
    const fxr_method *reach_method = fxr_registry_function(registry, "reach");
    fxr_value at;
    fxr_value_field(&v, "at", &at);
    fxr_value speed;
    fxr_value_field(&v, "speed", &speed);
    float answer = 0;
    const fxr_value args[] = {at, speed};
    const fxr_value result = fxr_value_make(f32, &answer);
    printf("reach(at, speed): %s = %g\n", status(fxr_method_call(reach_method, args, 2, &result)), (double)answer);

    printf("\n--- what the type comes to ---\n");
    fxr_type_describe(monster, text, sizeof text);
    printf("%s\nfingerprint %016llx\n", text, (unsigned long long)fxr_type_fingerprint(monster));

    fxr_arena_destroy(arena);
    fxr_registry_destroy(registry);
    return 0;
}
