/* SPDX-License-Identifier: BSL-1.0 */

/* What a type descriptor holds, laid out byte for byte as the Zig side lays
 * it out. */

#ifndef FLUXION_REFLECT_DESCRIPTORS_H
#define FLUXION_REFLECT_DESCRIPTORS_H

#include "base.h"

#ifdef __cplusplus
extern "C" {
#endif

enum fxr_kind {
    FXR_VOID,
    FXR_BOOL,
    FXR_INT,
    FXR_FLOAT,
    FXR_POINTER,
    FXR_SLICE,
    FXR_ARRAY,
    FXR_VECTOR,
    FXR_STRUCT,
    FXR_ENUM,
    FXR_UNION,
    FXR_OPTIONAL,
    FXR_ERROR_UNION,
    FXR_ERROR_SET,
    FXR_FUNCTION,
    FXR_OPAQUE,
    FXR_TYPE, /* a `const fxr_type*`: how a Zig `type` is kept at run time */
    FXR_NORETURN
};

enum fxr_pointer_size { FXR_POINTER_ONE, FXR_POINTER_MANY, FXR_POINTER_C };
enum fxr_layout { FXR_LAYOUT_AUTO, FXR_LAYOUT_EXTERN, FXR_LAYOUT_PACKED };
enum fxr_calling_convention { FXR_CALL_AUTO, FXR_CALL_C, FXR_CALL_OTHER };

typedef struct fxr_attribute {
    const fxr_type *type;
    const void *value;
} fxr_attribute;

typedef struct fxr_attribute_list {
    const fxr_attribute *ptr;
    size_t len;
} fxr_attribute_list;

/* A struct's field, or a union's arm. */
typedef struct fxr_field {
    fxr_str name;
    const fxr_type *type;
    /* Bytes from the start; for a bit field, the byte holding its lowest bit. */
    size_t offset;
    /* The declared default, or a comptime field's value. */
    const void *default_value;
    fxr_attribute_list attributes;
    /* Bits from the lowest bit of a packed container. */
    uint16_t bit_offset;
    bool is_comptime;
    bool is_bit_field;
} fxr_field;

typedef struct fxr_field_list {
    const fxr_field *ptr;
    size_t len;
} fxr_field_list;

typedef struct fxr_member {
    fxr_str name;
    /* Two's complement: read it as int64_t when the tag is signed. */
    uint64_t value;
    fxr_attribute_list attributes;
} fxr_member;

typedef struct fxr_member_list {
    const fxr_member *ptr;
    size_t len;
} fxr_member_list;

/* Calls the function whose pointer is kept at `function`, with args[i]
 * pointing at the i-th argument, and writes the result to `result`. */
typedef void (*fxr_invoke)(const void *function, void *const *args, void *result);

typedef struct fxr_method {
    fxr_str name;
    const fxr_type *type; /* an FXR_FUNCTION */
    const void *function;
    fxr_invoke invoke;
    fxr_attribute_list attributes;
} fxr_method;

typedef struct fxr_method_list {
    const fxr_method *ptr;
    size_t len;
} fxr_method_list;

typedef struct fxr_int_info {
    uint16_t bits;
    bool is_signed;
} fxr_int_info;

typedef struct fxr_float_info {
    uint16_t bits;
} fxr_float_info;

typedef struct fxr_pointer_info {
    const fxr_type *child;
    const void *sentinel;
    uint8_t size; /* enum fxr_pointer_size */
    bool is_const;
    bool is_volatile;
} fxr_pointer_info;

typedef struct fxr_raw_slice {
    void *ptr;
    size_t len;
} fxr_raw_slice;

typedef struct fxr_slice_ops {
    void (*get)(const void *slice, fxr_raw_slice *out);
    void (*set)(void *slice, const fxr_raw_slice *raw);
} fxr_slice_ops;

typedef struct fxr_slice_info {
    const fxr_type *child;
    const void *sentinel;
    /* NULL: a pointer and then a length, as C writes one. */
    const fxr_slice_ops *ops;
    bool is_const;
} fxr_slice_info;

typedef struct fxr_array_info {
    const fxr_type *child;
    size_t len;
    const void *sentinel;
} fxr_array_info;

typedef struct fxr_element_ops {
    void (*get)(const void *vector, size_t index, void *out);
    void (*set)(void *vector, size_t index, const void *in);
} fxr_element_ops;

typedef struct fxr_vector_info {
    const fxr_type *child;
    size_t len;
    const fxr_element_ops *ops;
} fxr_vector_info;

typedef struct fxr_struct_info {
    fxr_field_list fields;
    const fxr_type *backing; /* a packed struct's integer */
    uint8_t layout;          /* enum fxr_layout */
    bool is_tuple;
} fxr_struct_info;

typedef struct fxr_enum_info {
    const fxr_type *tag;
    fxr_member_list members;
    bool is_exhaustive;
} fxr_enum_info;

typedef struct fxr_union_ops {
    uint32_t (*active)(const void *u); /* NULL for an untagged union */
    void *(*payload)(void *u, uint32_t arm);
    void (*activate)(void *u, uint32_t arm);
} fxr_union_ops;

typedef struct fxr_union_info {
    fxr_field_list arms;
    const fxr_type *tag;
    /* NULL: every arm at the first byte and none known to be live, as in C. */
    const fxr_union_ops *ops;
    uint8_t layout;
} fxr_union_info;

typedef struct fxr_optional_ops {
    void *(*payload)(void *o);
    void (*set_null)(void *o);
    void *(*set_some)(void *o);
} fxr_optional_ops;

typedef struct fxr_optional_info {
    const fxr_type *child;
    const fxr_optional_ops *ops;
} fxr_optional_info;

typedef struct fxr_error_union_ops {
    void *(*payload)(void *e);
    uint32_t (*code)(const void *e);
    void (*set_code)(void *e, uint32_t code);
    void *(*set_payload)(void *e);
} fxr_error_union_ops;

typedef struct fxr_error_union_info {
    const fxr_type *error_set;
    const fxr_type *payload;
    const fxr_error_union_ops *ops;
} fxr_error_union_info;

typedef struct fxr_str_list {
    const fxr_str *ptr;
    size_t len;
} fxr_str_list;

typedef struct fxr_code_list {
    const uint32_t *ptr;
    size_t len;
} fxr_code_list;

typedef struct fxr_error_set_info {
    fxr_str_list names;
    fxr_code_list codes;
    bool is_any;
} fxr_error_set_info;

typedef struct fxr_param {
    const fxr_type *type;
    bool is_noalias;
} fxr_param;

typedef struct fxr_param_list {
    const fxr_param *ptr;
    size_t len;
} fxr_param_list;

typedef struct fxr_function_info {
    fxr_param_list params;
    const fxr_type *return_type;
    fxr_invoke invoke; /* NULL where nothing could be generated */
    uint8_t calling_convention; /* enum fxr_calling_convention */
    bool is_var_args;
} fxr_function_info;

/* Read the arm the type's kind names. */
typedef union fxr_info {
    fxr_int_info integer;
    fxr_float_info floating;
    fxr_pointer_info pointer;
    fxr_slice_info slice;
    fxr_array_info array;
    fxr_vector_info vector;
    fxr_struct_info structure;
    fxr_enum_info enumeration;
    fxr_union_info union_;
    fxr_optional_info optional;
    fxr_error_union_info error_union;
    fxr_error_set_info error_set;
    fxr_function_info function;
} fxr_info;

struct fxr_type {
    fxr_str name;
    uint64_t id; /* the name hashed: the same in every build */
    size_t size;
    const void *default_value;
    fxr_attribute_list attributes;
    fxr_method_list methods;
    uint32_t alignment;
    uint32_t bit_size;
    uint8_t kind; /* enum fxr_kind */
    fxr_info info;
};

const char *fxr_kind_name(uint8_t kind);

#ifdef __cplusplus
}
#endif

#endif
