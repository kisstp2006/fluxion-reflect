/* SPDX-License-Identifier: BSL-1.0 */

/* Every struct in the headers measured - size, alignment and the offset of
 * each field, in declaration order - for the Zig half to compare with its
 * own. */

#include "fluxion_reflect.h"

#define MEASURE(T)                  \
    do {                            \
        out[n++] = sizeof(T);       \
        out[n++] = FXR_ALIGNOF(T);  \
    } while (0)
#define AT(T, field) out[n++] = offsetof(T, field)

size_t fxr_test_layouts(size_t *out, size_t capacity) {
    size_t n = 0;
    if (capacity < 256) return 0;
    MEASURE(fxr_str); AT(fxr_str, ptr); AT(fxr_str, len);
    MEASURE(fxr_attribute); AT(fxr_attribute, type); AT(fxr_attribute, value);
    MEASURE(fxr_attribute_list); AT(fxr_attribute_list, ptr); AT(fxr_attribute_list, len);
    MEASURE(fxr_field); AT(fxr_field, name); AT(fxr_field, type); AT(fxr_field, offset); AT(fxr_field, default_value);
    AT(fxr_field, attributes); AT(fxr_field, bit_offset); AT(fxr_field, is_comptime); AT(fxr_field, is_bit_field);
    MEASURE(fxr_member); AT(fxr_member, name); AT(fxr_member, value); AT(fxr_member, attributes);
    MEASURE(fxr_method); AT(fxr_method, name); AT(fxr_method, type); AT(fxr_method, function); AT(fxr_method, invoke);
    AT(fxr_method, attributes);
    MEASURE(fxr_int_info); AT(fxr_int_info, bits); AT(fxr_int_info, is_signed);
    MEASURE(fxr_float_info); AT(fxr_float_info, bits);
    MEASURE(fxr_pointer_info); AT(fxr_pointer_info, child); AT(fxr_pointer_info, sentinel); AT(fxr_pointer_info, size);
    AT(fxr_pointer_info, is_const); AT(fxr_pointer_info, is_volatile);
    MEASURE(fxr_raw_slice); AT(fxr_raw_slice, ptr); AT(fxr_raw_slice, len);
    MEASURE(fxr_slice_ops); AT(fxr_slice_ops, get); AT(fxr_slice_ops, set);
    MEASURE(fxr_slice_info); AT(fxr_slice_info, child); AT(fxr_slice_info, sentinel); AT(fxr_slice_info, ops);
    AT(fxr_slice_info, is_const);
    MEASURE(fxr_array_info); AT(fxr_array_info, child); AT(fxr_array_info, len); AT(fxr_array_info, sentinel);
    MEASURE(fxr_element_ops); AT(fxr_element_ops, get); AT(fxr_element_ops, set);
    MEASURE(fxr_vector_info); AT(fxr_vector_info, child); AT(fxr_vector_info, len); AT(fxr_vector_info, ops);
    MEASURE(fxr_struct_info); AT(fxr_struct_info, fields); AT(fxr_struct_info, backing); AT(fxr_struct_info, layout);
    AT(fxr_struct_info, is_tuple);
    MEASURE(fxr_enum_info); AT(fxr_enum_info, tag); AT(fxr_enum_info, members); AT(fxr_enum_info, is_exhaustive);
    MEASURE(fxr_union_ops); AT(fxr_union_ops, active); AT(fxr_union_ops, payload); AT(fxr_union_ops, activate);
    MEASURE(fxr_union_info); AT(fxr_union_info, arms); AT(fxr_union_info, tag); AT(fxr_union_info, ops);
    AT(fxr_union_info, layout);
    MEASURE(fxr_optional_ops); AT(fxr_optional_ops, payload); AT(fxr_optional_ops, set_null); AT(fxr_optional_ops, set_some);
    MEASURE(fxr_optional_info); AT(fxr_optional_info, child); AT(fxr_optional_info, ops);
    MEASURE(fxr_error_union_ops); AT(fxr_error_union_ops, payload); AT(fxr_error_union_ops, code);
    AT(fxr_error_union_ops, set_code); AT(fxr_error_union_ops, set_payload);
    MEASURE(fxr_error_union_info); AT(fxr_error_union_info, error_set); AT(fxr_error_union_info, payload);
    AT(fxr_error_union_info, ops);
    MEASURE(fxr_error_set_info); AT(fxr_error_set_info, names); AT(fxr_error_set_info, codes); AT(fxr_error_set_info, is_any);
    MEASURE(fxr_param); AT(fxr_param, type); AT(fxr_param, is_noalias);
    MEASURE(fxr_function_info); AT(fxr_function_info, params); AT(fxr_function_info, return_type);
    AT(fxr_function_info, invoke); AT(fxr_function_info, calling_convention); AT(fxr_function_info, is_var_args);
    MEASURE(fxr_info);
    MEASURE(fxr_type); AT(fxr_type, name); AT(fxr_type, id); AT(fxr_type, size); AT(fxr_type, default_value);
    AT(fxr_type, attributes); AT(fxr_type, methods); AT(fxr_type, alignment); AT(fxr_type, bit_size); AT(fxr_type, kind);
    AT(fxr_type, info); AT(fxr_type, drop);
    MEASURE(fxr_value); AT(fxr_value, type); AT(fxr_value, ptr); AT(fxr_value, bit_offset); AT(fxr_value, is_bit_field);
    AT(fxr_value, is_const);
    MEASURE(fxr_bytes); AT(fxr_bytes, ptr); AT(fxr_bytes, len);
    MEASURE(fxr_field_desc); AT(fxr_field_desc, name); AT(fxr_field_desc, type); AT(fxr_field_desc, offset);
    MEASURE(fxr_struct_desc); AT(fxr_struct_desc, name); AT(fxr_struct_desc, size); AT(fxr_struct_desc, alignment);
    AT(fxr_struct_desc, fields); AT(fxr_struct_desc, field_count);
    MEASURE(fxr_member_desc); AT(fxr_member_desc, name); AT(fxr_member_desc, value);
    MEASURE(fxr_enum_desc); AT(fxr_enum_desc, name); AT(fxr_enum_desc, tag); AT(fxr_enum_desc, members);
    AT(fxr_enum_desc, member_count); AT(fxr_enum_desc, is_exhaustive);
    MEASURE(fxr_arm_desc); AT(fxr_arm_desc, name); AT(fxr_arm_desc, type);
    MEASURE(fxr_union_desc); AT(fxr_union_desc, name); AT(fxr_union_desc, size); AT(fxr_union_desc, alignment);
    AT(fxr_union_desc, arms); AT(fxr_union_desc, arm_count);
    MEASURE(fxr_function_desc); AT(fxr_function_desc, name); AT(fxr_function_desc, params);
    AT(fxr_function_desc, param_count); AT(fxr_function_desc, return_type); AT(fxr_function_desc, function);
    AT(fxr_function_desc, invoke);
    MEASURE(fxr_json_options); AT(fxr_json_options, indent); AT(fxr_json_options, sort_keys);
    AT(fxr_json_options, skip_defaults); AT(fxr_json_options, skip_nulls); AT(fxr_json_options, cbor);
    out[n++] = sizeof(fxr_status);
    out[n++] = FXR_UNKNOWN_TYPE;
    out[n++] = FXR_NORETURN;
    out[n++] = FXR_POINTER_C;
    out[n++] = FXR_LAYOUT_PACKED;
    out[n++] = FXR_CALL_OTHER;
    return n;
}
