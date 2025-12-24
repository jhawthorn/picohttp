# frozen_string_literal: true

require "test_helper"

class TestPicohttpEnv < Minitest::Test
  def test_parse_request_env_basic
    request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal({
      "REQUEST_METHOD" => "GET",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REQUEST_URI" => "/",
      "SCRIPT_NAME" => "",
      "HTTP_HOST" => "example.com",
      "SERVER_NAME" => "example.com",
    }, env)
  end

  def test_parse_request_env_with_query_string
    request = "GET /hello?name=world&foo=bar HTTP/1.0\r\nHost: localhost\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal({
      "REQUEST_METHOD" => "GET",
      "SERVER_PROTOCOL" => "HTTP/1.0",
      "PATH_INFO" => "/hello",
      "QUERY_STRING" => "name=world&foo=bar",
      "REQUEST_URI" => "/hello?name=world&foo=bar",
      "SCRIPT_NAME" => "",
      "HTTP_HOST" => "localhost",
      "SERVER_NAME" => "localhost",
    }, env)
  end

  def test_parse_request_env_header_name_transformation
    request = "POST /api HTTP/1.1\r\nContent-Type: application/json\r\nX-Custom-Header: test\r\naccept-encoding: gzip\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "POST", env["REQUEST_METHOD"]
    assert_equal "/api", env["PATH_INFO"]
    assert_equal "application/json", env["CONTENT_TYPE"]
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
    assert_equal "25", env["CONTENT_LENGTH"]
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

  def test_parse_request_env_very_long_header_name
    long_header_name = "X-" + "A" * 300  # 302 character header name
    request = "GET / HTTP/1.1\r\n#{long_header_name}: test\r\n\r\n"

    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request_env(request)
    end
    assert_equal "Header name too long", error.message
  end

  def test_parse_request_env_too_many_headers
    # Generate 150 headers (more than the 100 limit in picohttpparser)
    headers_str = 150.times.map { |i| "Header#{i}: value#{i}\r\n" }.join
    request = "GET / HTTP/1.1\r\n#{headers_str}\r\n"

    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request_env(request)
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_env_request_uri
    request = "GET /path?foo=bar HTTP/1.1\r\nHost: example.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "/path?foo=bar", env["REQUEST_URI"]
    assert_equal "/path", env["PATH_INFO"]
    assert_equal "foo=bar", env["QUERY_STRING"]
  end

  def test_parse_request_env_script_name
    request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "", env["SCRIPT_NAME"]
  end

  def test_parse_request_env_server_name_and_port
    request = "GET / HTTP/1.1\r\nHost: localhost:3000\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal({
      "REQUEST_METHOD" => "GET",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REQUEST_URI" => "/",
      "SCRIPT_NAME" => "",
      "HTTP_HOST" => "localhost:3000",
      "SERVER_NAME" => "localhost",
      "SERVER_PORT" => "3000",
    }, env)
  end

  def test_parse_request_env_server_name_without_port
    request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal "example.com", env["SERVER_NAME"]
    assert_nil env["SERVER_PORT"]
  end

  def test_parse_request_env_host_case_insensitive
    request = "GET / HTTP/1.1\r\nhost: localhost:8080\r\n\r\n"
    env = Picohttp.parse_request_env(request)

    assert_equal({
      "REQUEST_METHOD" => "GET",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REQUEST_URI" => "/",
      "SCRIPT_NAME" => "",
      "HTTP_HOST" => "localhost:8080",
      "SERVER_NAME" => "localhost",
      "SERVER_PORT" => "8080",
    }, env)
  end

  def test_parse_request_env_header_count_range
    (0..200).each do |num_headers|
      headers_str = "Host: localhost:3000\r\n"
      headers_str += num_headers.times.map { |i| "X-Header-#{i}: value#{i}\r\n" }.join
      request = "GET / HTTP/1.1\r\n#{headers_str}\r\n"

      if num_headers < 100
        env = Picohttp.parse_request_env(request)
        assert env
        assert_equal "GET", env["REQUEST_METHOD"]
        assert_equal "/", env["PATH_INFO"]
        assert_equal "localhost:3000", env["HTTP_HOST"]
        assert_equal num_headers + 1 + 8, env.size
      else
        assert_raises(Picohttp::ParseError) do
          Picohttp.parse_request_env(request)
        end
      end
    end
  end
end
