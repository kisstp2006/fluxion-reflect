/* SPDX-License-Identifier: BSL-1.0 */

#include "check.h"

static char *report;
static size_t report_capacity;
static size_t report_len;
static int failures;

static void put(const char *text) {
    for (; *text; text++) {
        if (report_len + 1 < report_capacity) report[report_len++] = *text;
    }
    if (report_capacity > 0) report[report_len < report_capacity ? report_len : report_capacity - 1] = 0;
}

static void put_number(long long n) {
    char digits[24];
    int i = 0;
    unsigned long long u = n < 0 ? (unsigned long long)(-(n + 1)) + 1 : (unsigned long long)n;
    if (n < 0) put("-");
    do {
        digits[i++] = (char)('0' + u % 10);
        u /= 10;
    } while (u > 0);
    char out[2] = {0, 0};
    while (i > 0) {
        out[0] = digits[--i];
        put(out);
    }
}

void check_begin(char *out, size_t capacity) {
    report = out;
    report_capacity = capacity;
    report_len = 0;
    failures = 0;
    put("");
}

int check_failures(void) { return failures; }

void check_fail(const char *file, int line, const char *what) {
    failures++;
    put(file);
    put(":");
    put_number(line);
    put(": ");
    put(what);
    put("\n");
}

bool same_text(const char *a, size_t a_len, const char *b) {
    size_t i = 0;
    for (; i < a_len; i++) {
        if (b[i] != a[i] || b[i] == 0) return false;
    }
    return b[i] == 0;
}

bool contains(const char *haystack, const char *needle) {
    if (!haystack) return false;
    for (; *haystack; haystack++) {
        const char *h = haystack;
        const char *n = needle;
        while (*n && *h == *n) {
            h++;
            n++;
        }
        if (*n == 0) return true;
    }
    return false;
}
