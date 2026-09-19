# frozen_string_literal: true

require "test_helper"

class TestPicohttpRactor < Minitest::Test
  def setup
    @original_experimental_warning = Warning[:experimental]
    Warning[:experimental] = false
  end

  def teardown
    Warning[:experimental] = @original_experimental_warning
  end

  def test_ractor_compatibility_env
    skip "Ractors not available" unless defined?(Ractor)

    request = "POST /api?foo=bar HTTP/1.0\r\nContent-Type: application/json\r\n\r\n"

    ractor = Ractor.new(request) do |req|
      Picohttp.parse_request_env(req)
    end

    env = ractor.value
    assert_equal "POST", env["REQUEST_METHOD"]
    assert_equal "/api", env["PATH_INFO"]
    assert_equal "foo=bar", env["QUERY_STRING"]
    assert_equal "HTTP/1.0", env["SERVER_PROTOCOL"]
    assert_equal "application/json", env["CONTENT_TYPE"]
  end

  TEMPLATE = Ractor.make_shareable({
    "rack.url_scheme" => "http",
    "rack.version" => [1, 3],
    "REMOTE_ADDR" => nil,
  })

  def test_ractor_compatibility_env_with_template
    skip "Ractors not available" unless defined?(Ractor)

    request = "POST /api?foo=bar HTTP/1.0\r\nContent-Type: application/json\r\n\r\n"

    ractor = Ractor.new(request) do |req|
      env = Picohttp.parse_request_env_with_template(req, TEMPLATE)
      env["REMOTE_ADDR"] = "127.0.0.1"
      env
    end

    env = ractor.value
    assert_equal "POST", env["REQUEST_METHOD"]
    assert_equal "foo=bar", env["QUERY_STRING"]
    assert_equal "http", env["rack.url_scheme"]
    assert_equal [1, 3], env["rack.version"]
    assert_equal "127.0.0.1", env["REMOTE_ADDR"]
    assert_nil TEMPLATE["REMOTE_ADDR"]
    assert_equal 3, TEMPLATE.size
  end
end if defined?(Ractor::Port)
