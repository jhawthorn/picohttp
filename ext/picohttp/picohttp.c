#include "picohttp.h"
#include "picohttpparser.h"

#define MAX_HEADER_NAME_LEN 256
#define MAX_HTTP_HEADERS 100
#define EXTRA_RACK_HEADERS 8

VALUE rb_mPicohttp;
VALUE rb_ePicohttpParseError;

// Frozen string constants
static VALUE rb_str_request_method;
static VALUE rb_str_server_protocol;
static VALUE rb_str_path_info;
static VALUE rb_str_query_string;
static VALUE rb_str_request_uri;
static VALUE rb_str_script_name;
static VALUE rb_str_server_name;
static VALUE rb_str_server_port;
static VALUE rb_str_empty;
static VALUE rb_str_http_1_0;
static VALUE rb_str_http_1_1;

#include "string_lookup.inc"

static VALUE
http_version_string(int minor_version)
{
    if (minor_version == 0) {
        return rb_str_http_1_0;
    } else if (minor_version == 1) {
        return rb_str_http_1_1;
    } else {
        return rb_sprintf("HTTP/1.%d", minor_version);
    }
}

static VALUE
http_method_string(const char *method, size_t method_len)
{
    VALUE str = lookup_method(method, method_len);
    if (str == Qnil) str = rb_str_new(method, method_len);
    return str;
}

static VALUE
header_name_to_env_key(const char *name, size_t name_len)
{
    if (name_len > MAX_HEADER_NAME_LEN) {
        rb_raise(rb_ePicohttpParseError, "Header name too long");
    }

    VALUE str = lookup_header(name, name_len);
    if (str != Qnil) {
        return str;
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
    struct phr_header headers[MAX_HTTP_HEADERS];
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
    struct phr_header headers[MAX_HTTP_HEADERS];
    size_t method_len, path_len, num_headers = sizeof(headers) / sizeof(headers[0]);

    int result = phr_parse_request(buf, len, &method, &method_len, &path, &path_len,
                                   &minor_version, headers, &num_headers, 0);

    if (result < 0) {
        if (result == -2) {
            return Qnil; // Incomplete request
        }
        rb_raise(rb_ePicohttpParseError, "Invalid HTTP request");
    }

    VALUE header_values[(MAX_HTTP_HEADERS + EXTRA_RACK_HEADERS) * 2];
    int idx = 0;

    // Standard CGI/Rack environment variables
    header_values[idx++] = rb_str_request_method;
    header_values[idx++] = http_method_string(method, method_len);

    header_values[idx++] = rb_str_server_protocol;
    header_values[idx++] = http_version_string(minor_version);

    // Parse path and query string in C
    const char *query_start = memchr(path, '?', path_len);
    if (query_start) {
        size_t path_info_len = query_start - path;
        size_t query_len = path_len - path_info_len - 1;

        header_values[idx++] = rb_str_path_info;
        header_values[idx++] = rb_str_new(path, path_info_len);

        header_values[idx++] = rb_str_query_string;
        header_values[idx++] = rb_str_new(query_start + 1, query_len);
    } else {
        header_values[idx++] = rb_str_path_info;
        header_values[idx++] = rb_str_new(path, path_len);

        header_values[idx++] = rb_str_query_string;
        header_values[idx++] = rb_str_empty;
    }

    // REQUEST_URI is the full path including query string
    header_values[idx++] = rb_str_request_uri;
    header_values[idx++] = rb_str_new(path, path_len);

    // SCRIPT_NAME is always empty
    header_values[idx++] = rb_str_script_name;
    header_values[idx++] = rb_str_empty;

    // Convert headers to HTTP_ prefixed environment variables
    for (size_t i = 0; i < num_headers; i++) {
        if (headers[i].name == NULL) {
            rb_raise(rb_ePicohttpParseError, "HTTP line folding not supported");
        }

        header_values[idx++] = header_name_to_env_key(headers[i].name, headers[i].name_len);
        header_values[idx++] = rb_str_new(headers[i].value, headers[i].value_len);

        // Extract SERVER_NAME/SERVER_PORT from Host header
        if (headers[i].name_len == 4 &&
            (headers[i].name[0] | 0x20) == 'h' &&
            (headers[i].name[1] | 0x20) == 'o' &&
            (headers[i].name[2] | 0x20) == 's' &&
            (headers[i].name[3] | 0x20) == 't') {
            const char *host = headers[i].value;
            size_t host_len = headers[i].value_len;
            const char *colon = memchr(host, ':', host_len);

            if (colon) {
                header_values[idx++] = rb_str_server_name;
                header_values[idx++] = rb_str_new(host, colon - host);
                header_values[idx++] = rb_str_server_port;
                header_values[idx++] = rb_str_new(colon + 1, host_len - (colon - host) - 1);
            } else {
                header_values[idx++] = rb_str_server_name;
                header_values[idx++] = rb_str_new(host, host_len);
            }
        }
    }

#ifdef HAVE_RB_HASH_NEW_CAPA
    VALUE env = rb_hash_new_capa(idx / 2);
#else
    VALUE env = rb_hash_new();
#endif

    rb_hash_bulk_insert(idx, header_values, env);

    return env;
}

static VALUE
register_interned_string(const char *str)
{
    VALUE val = rb_interned_str_cstr(str);
    rb_gc_register_mark_object(val);
    return val;
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
    init_string_lookup();

    rb_str_request_method = register_interned_string("REQUEST_METHOD");
    rb_str_server_protocol = register_interned_string("SERVER_PROTOCOL");
    rb_str_path_info = register_interned_string("PATH_INFO");
    rb_str_query_string = register_interned_string("QUERY_STRING");
    rb_str_request_uri = register_interned_string("REQUEST_URI");
    rb_str_script_name = register_interned_string("SCRIPT_NAME");
    rb_str_server_name = register_interned_string("SERVER_NAME");
    rb_str_server_port = register_interned_string("SERVER_PORT");
    rb_str_empty = register_interned_string("");
    rb_str_http_1_0 = register_interned_string("HTTP/1.0");
    rb_str_http_1_1 = register_interned_string("HTTP/1.1");
}
