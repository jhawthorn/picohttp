#include "picohttp.h"
#include "picohttpparser.h"

VALUE rb_mPicohttp;

static VALUE
picohttp_parse_request(VALUE self, VALUE str)
{
    Check_Type(str, T_STRING);

    const char *buf = RSTRING_PTR(str);
    size_t len = RSTRING_LEN(str);

    const char *method, *path;
    int minor_version;
    struct phr_header headers[100];
    size_t method_len, path_len, num_headers = sizeof(headers) / sizeof(headers[0]);

    int result = phr_parse_request(buf, len, &method, &method_len, &path, &path_len,
                                   &minor_version, headers, &num_headers, 0);

    if (result < 0) {
        if (result == -2) {
            return Qnil; // Incomplete request
        }
        rb_raise(rb_eArgError, "Failed to parse HTTP request");
    }

    VALUE headers_hash = rb_hash_new();
    for (size_t i = 0; i < num_headers; i++) {
        VALUE key = rb_str_new(headers[i].name, headers[i].name_len);
        VALUE val = rb_str_new(headers[i].value, headers[i].value_len);
        rb_hash_aset(headers_hash, key, val);
    }

    return rb_ary_new_from_args(5,
        rb_str_new(method, method_len),
        rb_str_new(path, path_len),
        rb_sprintf("1.%d", minor_version),
        headers_hash,
        INT2FIX(result));
}

RUBY_FUNC_EXPORTED void
Init_picohttp(void)
{
    rb_mPicohttp = rb_define_module("Picohttp");
    rb_define_module_function(rb_mPicohttp, "parse_request", picohttp_parse_request, 1);
}
