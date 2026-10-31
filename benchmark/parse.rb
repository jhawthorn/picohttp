# frozen_string_literal: true

# Compares request parsing against other Ruby HTTP servers' parsers.
#
#   gem install ips puma unicorn webrick protocol-http1 protocol-rack
#   bundle exec rake compile && ruby benchmark/parse.rb

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ips"
require "stringio"
require "picohttp"
require "puma"
require "puma/puma_http11"
require "unicorn"
require "webrick"
require "protocol/http1"
require "protocol/rack"

REQUEST = "GET /api/users?limit=10 HTTP/1.1\r\n" \
          "Host: api.example.com\r\n" \
          "User-Agent: Mozilla/5.0 (X11; Linux x86_64)\r\n" \
          "Accept: text/html,application/xhtml+xml\r\n" \
          "Accept-Language: en-US,en;q=0.9\r\n" \
          "Accept-Encoding: gzip, deflate\r\n" \
          "Cookie: session=abcdef0123456789\r\n" \
          "\r\n"

puma = Puma::HttpParser.new
unicorn = Unicorn::HttpParser.new
falcon = Protocol::Rack::Adapter.new(->(env) { [200, {}, []] })
webrick_config = WEBrick::Config::HTTP

IPS.ips do |x|
  x.report("picohttp") { Picohttp.parse_request_env(REQUEST) }
  # Puma and Unicorn rewrite header names in place (X-Y -> X_Y), so each parse needs a fresh buffer
  x.report("puma") do
    puma.reset
    puma.execute({}, REQUEST.dup, 0)
  end
  x.report("unicorn") do
    unicorn.clear
    unicorn.headers({}, REQUEST.dup)
  end
  # Falcon: protocol-http1 parses the request, then protocol-rack builds the env.
  # A Connection is single-request state, so build one per parse.
  x.report("falcon") do
    authority, method, path, version, headers, body = Protocol::HTTP1::Connection.new(StringIO.new(REQUEST)).read_request
    request = Protocol::HTTP::Request.new("http", authority, method, path, version, headers, body)
    falcon.make_environment(request)
  end
  x.report("webrick") { WEBrick::HTTPRequest.new(webrick_config).parse(StringIO.new(REQUEST)) }
end
