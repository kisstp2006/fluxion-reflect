/* SPDX-License-Identifier: BSL-1.0 */

/* The Zig hero's type, read from C: the descriptor directly, and through
 * types.h. */

#include "check.h"

void test_types(const fxr_registry *registry, const fxr_value *hero) {
    CHECK(fxr_abi_version() == FXR_ABI_VERSION);
    CHECK(contains(fxr_status_name(FXR_NO_SUCH_FIELD), "no_such_field"));
    CHECK(contains(fxr_kind_name(FXR_STRUCT), "struct"));

    const fxr_type *hero_type = fxr_registry_find(registry, "Hero");
    CHECK(hero_type != 0);
    if (!hero_type) return;
    CHECK(hero_type == hero->type);
    CHECK(hero_type->kind == FXR_STRUCT);
    CHECK(same_text(hero_type->name.ptr, hero_type->name.len, "Hero"));
    CHECK(hero_type->info.structure.fields.len == 8);

    const fxr_field *level_field = fxr_type_field(hero_type, "level");
    CHECK(level_field != 0);
    if (level_field) {
        CHECK(level_field->type == fxr_registry_find(registry, "u16"));
        CHECK(level_field->type->info.integer.bits == 16 && !level_field->type->info.integer.is_signed);
        CHECK(!level_field->is_comptime && !level_field->is_bit_field);
    }
    CHECK(!hero_type->info.structure.is_tuple && hero_type->info.structure.layout == FXR_LAYOUT_AUTO);
    for (size_t i = 0; i < hero_type->info.structure.fields.len; i++) {
        const fxr_field *f = &hero_type->info.structure.fields.ptr[i];
        CHECK(f->is_comptime == false);
        if (f->type->kind == FXR_ENUM) CHECK(f->type->info.enumeration.is_exhaustive);
        if (f->type->kind == FXR_SLICE) CHECK(f->type->info.slice.is_const);
        if (f->type->kind == FXR_STRUCT && f->type->info.structure.layout == FXR_LAYOUT_PACKED) {
            CHECK(f->type->info.structure.fields.ptr[1].is_bit_field);
            CHECK(f->type->info.structure.fields.ptr[1].bit_offset == 1);
        }
    }
    CHECK(fxr_registry_find(registry, "i32")->info.integer.is_signed);
    CHECK(fxr_type_field(hero_type, "nope") == 0);
    CHECK(contains(fxr_type_suggest(hero_type, "helth"), "health"));

    char buffer[256];
    CHECK(fxr_type_describe(hero_type, buffer, sizeof buffer) > 0 && contains(buffer, "struct{name:[]u8,level:u16"));
    CHECK(fxr_type_fingerprint(hero_type) != 0);
}
