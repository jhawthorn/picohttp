# frozen_string_literal: true

require "test_helper"

class TestPicohttpRactor < Minitest::Test
  def test_ractor_compatibility_env
    skip "Ractors not available" unless defined?(Ractor)

    request = "POST /api?foo=bar HTTP/1.0\r\nContent-Type: application/json\r\n\r\n"

    ractor = Ractor.new(request) do |req|
      require "picohttp"
      Picohttp.parse_request_env(req)
    end

    env = ractor.value
    assert_equal "POST", env["REQUEST_METHOD"]
    assert_equal "/api", env["PATH_INFO"]
    assert_equal "foo=bar", env["QUERY_STRING"]
    assert_equal "HTTP/1.0", env["SERVER_PROTOCOL"]
    assert_equal "application/json", env["HTTP_CONTENT_TYPE"]
  end
end if defined?(Ractor::Port)
