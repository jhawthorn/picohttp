#include "picohttp.h"
#include "picohttpparser.h"

#define MAX_HEADER_NAME_LEN 256

VALUE rb_mPicohttp;
VALUE rb_ePicohttpParseError;

// Frozen string constants
static VALUE rb_str_request_method;
static VALUE rb_str_server_protocol;
static VALUE rb_str_path_info;
static VALUE rb_str_query_string;
static VALUE rb_str_empty;

static VALUE
header_name_to_env_key(const char *name, size_t name_len)
{
    if (name_len > MAX_HEADER_NAME_LEN) {
        rb_raise(rb_ePicohttpParseError, "Header name too long");
    }

    char env_name[MAX_HEADER_NAME_LEN + 6]; // "HTTP_" + name + null terminator
    strcpy(env_name, "HTTP_");

    for (size_t j = 0; j < name_len; j++) {
        char c = name[j];
        if (c == '-') {
            env_name[5 + j] = '_';
        } else if (c >= 'a' && c <= 'z') {
            env_name[5 + j] = c - 'a' + 'A';
        } else {
            env_name[5 + j] = c;
        }
    }
    env_name[5 + name_len] = '\0';

    return rb_interned_str(env_name, 5 + name_len);
}

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
        rb_raise(rb_ePicohttpParseError, "Invalid HTTP request");
    }

    VALUE headers_hash = rb_hash_new();
    for (size_t i = 0; i < num_headers; i++) {
        if (headers[i].name == NULL) {
            rb_raise(rb_ePicohttpParseError, "HTTP line folding not supported");
        }
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

static VALUE
picohttp_parse_request_env(VALUE self, VALUE str)
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
        rb_raise(rb_ePicohttpParseError, "Invalid HTTP request");
    }

    VALUE env = rb_hash_new();

    // Standard CGI/Rack environment variables
    rb_hash_aset(env, rb_str_request_method, rb_str_new(method, method_len));
    rb_hash_aset(env, rb_str_server_protocol, rb_sprintf("HTTP/1.%d", minor_version));

    // Parse path and query string in C
    const char *query_start = memchr(path, '?', path_len);
    if (query_start) {
        size_t path_info_len = query_start - path;
        size_t query_len = path_len - path_info_len - 1;
        rb_hash_aset(env, rb_str_path_info, rb_str_new(path, path_info_len));
        rb_hash_aset(env, rb_str_query_string, rb_str_new(query_start + 1, query_len));
    } else {
        rb_hash_aset(env, rb_str_path_info, rb_str_new(path, path_len));
        rb_hash_aset(env, rb_str_query_string, rb_str_empty);
    }

    // Convert headers to HTTP_ prefixed environment variables
    for (size_t i = 0; i < num_headers; i++) {
        if (headers[i].name == NULL) {
            rb_raise(rb_ePicohttpParseError, "HTTP line folding not supported");
        }

        VALUE header_name = header_name_to_env_key(headers[i].name, headers[i].name_len);
        VALUE header_value = rb_str_new(headers[i].value, headers[i].value_len);
        rb_hash_aset(env, header_name, header_value);
    }

    return env;
}

RUBY_FUNC_EXPORTED void
Init_picohttp(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

    rb_mPicohttp = rb_define_module("Picohttp");
    rb_ePicohttpParseError = rb_define_class_under(rb_mPicohttp, "ParseError", rb_eStandardError);
    rb_define_module_function(rb_mPicohttp, "parse_request", picohttp_parse_request, 1);
    rb_define_module_function(rb_mPicohttp, "parse_request_env", picohttp_parse_request_env, 1);

    // Initialize interned string constants
    rb_str_request_method = rb_interned_str_cstr("REQUEST_METHOD");
    rb_str_server_protocol = rb_interned_str_cstr("SERVER_PROTOCOL");
    rb_str_path_info = rb_interned_str_cstr("PATH_INFO");
    rb_str_query_string = rb_interned_str_cstr("QUERY_STRING");
    rb_str_empty = rb_interned_str_cstr("");

    // Prevent garbage collection of constants
    rb_gc_register_address(&rb_str_request_method);
    rb_gc_register_address(&rb_str_server_protocol);
    rb_gc_register_address(&rb_str_path_info);
    rb_gc_register_address(&rb_str_query_string);
    rb_gc_register_address(&rb_str_empty);
}
