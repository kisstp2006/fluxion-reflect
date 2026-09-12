/* SPDX-License-Identifier: BSL-1.0 */

/* What every part of the C test shares: checks that add to a report instead
 * of stopping, and the parts, one per header. No C library is used, so the
 * same files run in a browser. */

#ifndef FXR_TEST_CHECK_H
#define FXR_TEST_CHECK_H

#include "fluxion_reflect.h"

void check_begin(char *report, size_t capacity);
int check_failures(void);
void check_fail(const char *file, int line, const char *what);
bool same_text(const char *a, size_t a_len, const char *b);
bool contains(const char *haystack, const char *needle);

#define CHECK(condition)                                          \
    do {                                                          \
        if (!(condition)) check_fail(__FILE__, __LINE__, #condition); \
    } while (0)

#define OK(call) CHECK((call) == FXR_OK)

void test_types(const fxr_registry *registry, const fxr_value *hero);
void test_values(const fxr_value *hero, fxr_arena *arena);
void test_calls(const fxr_registry *registry, const fxr_value *hero);
void test_json(const fxr_value *hero, fxr_arena *arena);
void test_registry(fxr_registry *registry);

#endif
