/* SPDX-License-Identifier: BSL-1.0 */

/* The hero as JSON and as CBOR through json.h, and read back into a fresh
 * value that then equals it. */

#include "check.h"

void test_json(const fxr_value *hero, fxr_arena *arena) {
    char json[512];
    size_t json_len = 0;
    fxr_value copy;
    OK(fxr_value_to_json(hero, 0, json, sizeof json, &json_len));
    CHECK(json_len < sizeof json && contains(json, "\"level\":7") && contains(json, "\"items\":[\"rope\",\"lamp\"]"));
    OK(fxr_value_create(hero->type, &copy));
    OK(fxr_value_from_json(&copy, json, json_len, arena));
    CHECK(fxr_value_eql(&copy, hero));
    CHECK(fxr_value_from_json(&copy, json, json_len, 0) == FXR_NULL);
    CHECK(fxr_value_from_json(&copy, "{\"level\": 70000}", 16, arena) == FXR_OUT_OF_RANGE);
    fxr_value_destroy(&copy);

    const fxr_json_options cbor = {0, false, false, false, true};
    OK(fxr_value_to_json(hero, &cbor, json, sizeof json, &json_len));
    CHECK(json_len < sizeof json && (unsigned char)json[0] == 0xD9);
    OK(fxr_value_create(hero->type, &copy));
    OK(fxr_value_from_json(&copy, json, json_len, arena));
    CHECK(fxr_value_eql(&copy, hero));
    fxr_value_destroy(&copy);

    const fxr_json_options pretty = {2, true, false, false, false};
    OK(fxr_value_to_json(hero, &pretty, json, sizeof json, &json_len));
    CHECK(contains(json, "\n  \"flags\": "));
}
