# frozen_string_literal: true

require "test_helper"

class TestPicohttp < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Picohttp::VERSION
  end

  def test_parse_request_simple
    method, path, version, headers, offset = Picohttp.parse_request("GET / HTTP/1.0\r\n\r\n")
    assert_equal "GET", method
    assert_equal "/", path
    assert_equal "1.0", version
    assert_equal({}, headers)
    assert_equal 18, offset
  end

  def test_parse_request_with_headers
    request = "GET /hoge HTTP/1.1\r\nHost: example.com\r\nCookie: \r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal "/hoge", path
    assert_equal "1.1", version
    assert_equal "example.com", headers["Host"]
    assert_equal "", headers["Cookie"]
    assert_equal request.bytesize, offset
  end

  def test_parse_request_partial
    # Incomplete request should return nil
    assert_nil Picohttp.parse_request("GET / HTTP/1.0\r\n\r")
    assert_nil Picohttp.parse_request("GET / HTTP/1.0\r\n")
    assert_nil Picohttp.parse_request("GET / HTTP/1.0\r")
    assert_nil Picohttp.parse_request("GET / HTTP/1.0")
    assert_nil Picohttp.parse_request("GET / HTTP/")
    assert_nil Picohttp.parse_request("GET / ")
    assert_nil Picohttp.parse_request("GET /")
    assert_nil Picohttp.parse_request("GET ")
    assert_nil Picohttp.parse_request("GET")
  end

  def test_parse_request_multiple_headers
    request = "POST /users HTTP/1.0\r\n" +
              "Host: localhost\r\n" +
              "Content-Type: application/json\r\n" +
              "Content-Length: 13\r\n" +
              "Accept: */*\r\n" +
              "\r\n"

    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "POST", method
    assert_equal "/users", path
    assert_equal "1.0", version
    assert_equal "localhost", headers["Host"]
    assert_equal "application/json", headers["Content-Type"]
    assert_equal "13", headers["Content-Length"]
    assert_equal "*/*", headers["Accept"]
    assert_equal request.bytesize, offset
  end

  def test_parse_request_with_query_string
    request = "GET /path?foo=bar&baz=qux HTTP/1.1\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal "/path?foo=bar&baz=qux", path
    assert_equal "1.1", version
  end

  def test_parse_request_with_fragment
    request = "GET /path#section HTTP/1.0\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal "/path#section", path
    assert_equal "1.0", version
  end

  def test_parse_request_multiline_headers
    request = "GET / HTTP/1.0\r\nfoo: \r\nfoo: b\r\n  \tc\r\n\r\n"
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request(request)
    end
    assert_equal "HTTP line folding not supported", error.message
  end

  def test_parse_request_with_trailing_space_in_header_name
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request("GET / HTTP/1.0\r\nfoo : ab\r\n\r\n")
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_empty_header_value
    request = "GET / HTTP/1.1\r\nHost:\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "", headers["Host"]
  end

  def test_parse_request_header_value_with_spaces
    request = "GET / HTTP/1.1\r\nHost: example.com \r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "example.com", headers["Host"]
  end

  def test_parse_request_multiple_spaces_between_tokens
    request = "GET   /   HTTP/1.0\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal "/", path
    assert_equal "1.0", version
  end

  def test_parse_request_all_methods
    %w[GET HEAD POST PUT DELETE CONNECT OPTIONS TRACE PATCH].each do |meth|
      request = "#{meth} / HTTP/1.0\r\n\r\n"
      method, path, version, headers, offset = Picohttp.parse_request(request)
      assert_equal meth, method
    end
  end

  def test_parse_request_custom_method
    # Should accept any token as method
    request = "CUSTOM /path HTTP/1.1\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "CUSTOM", method
    assert_equal "/path", path
  end

  def test_parse_request_http_versions
    %w[1.0 1.1].each do |ver|
      request = "GET / HTTP/#{ver}\r\n\r\n"
      method, path, version, headers, offset = Picohttp.parse_request(request)
      assert_equal ver, version
    end
  end

  def test_parse_request_http_09
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request("GET /\r\n\r\n")
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_empty_method
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request(" / HTTP/1.0\r\n\r\n")
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_empty_path
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request("GET  HTTP/1.0\r\n\r\n")
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_invalid_characters
    # NUL character in request
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request("GET /\x00 HTTP/1.0\r\n\r\n")
    end
    assert_equal "Invalid HTTP request", error.message

    # Control characters in headers
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request("GET / HTTP/1.0\r\nHost: exa\x01mple.com\r\n\r\n")
    end
    assert_equal "Invalid HTTP request", error.message
  end

  def test_parse_request_very_long_path
    long_path = "/" + "a" * 5000
    request = "GET #{long_path} HTTP/1.0\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal long_path, path
  end

  def test_parse_request_many_headers
    headers_str = 50.times.map { |i| "Header#{i}: value#{i}\r\n" }.join
    request = "GET / HTTP/1.1\r\n#{headers_str}\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal 50, headers.size
    50.times do |i|
      assert_equal "value#{i}", headers["Header#{i}"]
    end
  end

  def test_parse_request_duplicate_headers
    # When same header appears multiple times, last one wins
    request = "GET / HTTP/1.0\r\nHost: first.com\r\nHost: second.com\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "second.com", headers["Host"]
  end

  def test_parse_request_case_sensitive_headers
    request = "GET / HTTP/1.0\r\nHost: example.com\r\nhost: other.com\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    # Headers are case-sensitive as returned
    assert_equal "example.com", headers["Host"]
    assert_equal "other.com", headers["host"]
  end

  def test_parse_request_with_body
    request = "POST / HTTP/1.1\r\nContent-Length: 13\r\n\r\n{\"test\":true}"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "POST", method
    assert_equal "/", path
    # offset should point to start of body
    assert_equal request.index("{"), offset
    assert_equal '{"test":true}', request[offset..-1]
  end

  def test_parse_request_line_folding
    request = "GET / HTTP/1.0\r\nHost: example\r\n .com\r\n\r\n"
    error = assert_raises(Picohttp::ParseError) do
      Picohttp.parse_request(request)
    end
    assert_equal "HTTP line folding not supported", error.message
  end

  def test_parse_request_header_without_space_after_colon
    request = "GET / HTTP/1.0\r\nHost:example.com\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "example.com", headers["Host"]
  end

  def test_parse_request_tab_in_header_value
    request = "GET / HTTP/1.0\r\nHost:\texample.com\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "example.com", headers["Host"]
  end

  def test_parse_request_absolute_uri
    request = "GET http://example.com/path HTTP/1.1\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal "http://example.com/path", path
    assert_equal "1.1", version
  end

  def test_parse_request_asterisk_form
    request = "OPTIONS * HTTP/1.1\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "OPTIONS", method
    assert_equal "*", path
    assert_equal "1.1", version
  end

  def test_parse_request_multibyte_characters
    request = "GET /hoge HTTP/1.1\r\nUser-Agent: \343\201\262\343/1.0\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "GET", method
    assert_equal "/hoge", path
    assert_equal "\xE3\x81\xB2\xE3/1.0".b, headers["User-Agent"]
  end

  def test_parse_request_chunked_encoding
    request = "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
    method, path, version, headers, offset = Picohttp.parse_request(request)
    assert_equal "POST", method
    assert_equal "chunked", headers["Transfer-Encoding"]
    # Body parsing would start at offset
    assert_equal request.index("\r\n\r\n") + 4, offset
  end
end
