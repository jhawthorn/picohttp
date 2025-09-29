# frozen_string_literal: true

require "test_helper"

class TestPicohttpEnv < Minitest::Test
  def test_parse_request_env_basic
    request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "GET", env["REQUEST_METHOD"]
    assert_equal "HTTP/1.1", env["SERVER_PROTOCOL"]
    assert_equal "/", env["PATH_INFO"]
    assert_equal "", env["QUERY_STRING"]
    assert_equal "example.com", env["HTTP_HOST"]
  end

  def test_parse_request_env_with_query_string
    request = "GET /hello?name=world&foo=bar HTTP/1.0\r\nHost: localhost\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "GET", env["REQUEST_METHOD"]
    assert_equal "HTTP/1.0", env["SERVER_PROTOCOL"]
    assert_equal "/hello", env["PATH_INFO"]
    assert_equal "name=world&foo=bar", env["QUERY_STRING"]
    assert_equal "localhost", env["HTTP_HOST"]
  end

  def test_parse_request_env_header_name_transformation
    request = "POST /api HTTP/1.1\r\nContent-Type: application/json\r\nX-Custom-Header: test\r\naccept-encoding: gzip\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "POST", env["REQUEST_METHOD"]
    assert_equal "/api", env["PATH_INFO"]
    assert_equal "application/json", env["HTTP_CONTENT_TYPE"]
    assert_equal "test", env["HTTP_X_CUSTOM_HEADER"]
    assert_equal "gzip", env["HTTP_ACCEPT_ENCODING"]
  end

  def test_parse_request_env_multiple_headers
    request = "PUT /users/123 HTTP/1.1\r\n" +
              "Host: api.example.com\r\n" +
              "User-Agent: MyApp/1.0\r\n" +
              "Authorization: Bearer token123\r\n" +
              "Content-Length: 25\r\n" +
              "\r\n"

    env = Picohttp.parse_request_env(request)

    assert_equal "PUT", env["REQUEST_METHOD"]
    assert_equal "/users/123", env["PATH_INFO"]
    assert_equal "api.example.com", env["HTTP_HOST"]
    assert_equal "MyApp/1.0", env["HTTP_USER_AGENT"]
    assert_equal "Bearer token123", env["HTTP_AUTHORIZATION"]
    assert_equal "25", env["HTTP_CONTENT_LENGTH"]
  end

  def test_parse_request_env_no_query_string
    request = "DELETE /posts/456 HTTP/1.1\r\nHost: blog.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "DELETE", env["REQUEST_METHOD"]
    assert_equal "/posts/456", env["PATH_INFO"]
    assert_equal "", env["QUERY_STRING"]
  end

  def test_parse_request_env_empty_query_string
    request = "GET /search? HTTP/1.1\r\nHost: search.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "/search", env["PATH_INFO"]
    assert_equal "", env["QUERY_STRING"]
  end

  def test_parse_request_env_incomplete_request
    request = "GET /incomplete HTTP/1.1\r\nHost: example.com\r\n"
    result = Picohttp.parse_request_env(request)

    assert_nil result
  end

  def test_parse_request_env_malformed_request
    request = "GET /\x00 HTTP/1.0\r\n\r\n"

    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request_env(request)
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_env_line_folding_error
    request = "GET / HTTP/1.0\r\nHost: example\r\n .com\r\n\r\n"

    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request_env(request)
    end
    assert_equal "HTTP line folding not supported", error.message
  end

  def test_parse_request_env_complex_path
    request = "GET /api/v1/users/123/posts?limit=10&offset=20 HTTP/1.1\r\nHost: api.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "/api/v1/users/123/posts", env["PATH_INFO"]
    assert_equal "limit=10&offset=20", env["QUERY_STRING"]
  end

  def test_parse_request_env_header_case_preservation
    request = "GET / HTTP/1.1\r\nHost: example.com\r\nHOST: other.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    # Both should be converted to HTTP_HOST, last one wins
    assert_equal "other.com", env["HTTP_HOST"]
  end

  def test_parse_request_env_special_characters_in_headers
    request = "GET / HTTP/1.1\r\nX-Test-123: value with spaces\r\nX_Under_Score: underscore\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "value with spaces", env["HTTP_X_TEST_123"]
    assert_equal "underscore", env["HTTP_X_UNDER_SCORE"]
  end
end
