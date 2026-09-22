# Picohttp

Fast HTTP request parser using picohttpparser.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add picohttp
```

## Usage

```ruby
require 'picohttp'

request = "GET /api/users?limit=10 HTTP/1.1\r\n" +
          "Host: api.example.com\r\n" +
          "User-Agent: MyApp/1.0\r\n" +
          "\r\n"

# Rack-compatible environment hash
env = Picohttp.parse_request_env(request)
# => {
#      "REQUEST_METHOD" => "GET",
#      "PATH_INFO" => "/api/users",
#      "QUERY_STRING" => "limit=10",
#      "SERVER_PROTOCOL" => "HTTP/1.1",
#      "HTTP_HOST" => "api.example.com",
#      "HTTP_USER_AGENT" => "MyApp/1.0"
#    }
```

Returns `nil` for incomplete requests, raises `Picohttp::ParseError` for invalid ones.

### Environment fields

The produced hash uses CGI/Rack-style keys:

| Key               | Value                                                                                                | Set when |
| ----------------- | --------------------------------------------------------------------------------------------------- | -------- |
| `REQUEST_METHOD`  | The request method, e.g. `"GET"`, `"POST"`.                                                          | always   |
| `SCRIPT_NAME`     | Always `""`.                                                                                         | always   |
| `PATH_INFO`       | The request path with any query string removed, e.g. `"/api/users"`.                                | always   |
| `QUERY_STRING`    | The part of the target after `?`, or `""` when there is none.                                        | always   |
| `REQUEST_URI`     | The full request target, e.g. `"/api/users?limit=10"`.                                               | always   |
| `SERVER_PROTOCOL` | `"HTTP/1.0"` or `"HTTP/1.1"`.                                                                        | always   |
| `SERVER_NAME`     | The host portion of the `Host` header, with brackets kept for IPv6 literals (`"[::1]"`).             | `Host` present |
| `SERVER_PORT`     | The port from the `Host` header, e.g. `"8080"`.                                                      | `Host` has a port |
| `CONTENT_TYPE`    | The `Content-Type` header (note: no `HTTP_` prefix).                                                 | header present |
| `CONTENT_LENGTH`  | The `Content-Length` header (note: no `HTTP_` prefix).                                               | header present |

Every other request header becomes an `HTTP_`-prefixed key: the name is
uppercased and `-` becomes `_` (e.g. `User-Agent` → `HTTP_USER_AGENT`). Repeated
headers are joined with `, `. A repeated `Host` header raises
`Picohttp::ParseError` (RFC 7230 §5.4).

### Starting from a template

Servers usually add the same constant keys to every env. `parse_request_env_with_template` starts from a copy of a template hash instead, which is faster than merging the constants in afterwards:

```ruby
RACK_ENV_CONST = {
  "rack.url_scheme" => "http",
  "SERVER_SOFTWARE" => "MyServer/1.0",
}.freeze

env = Picohttp.parse_request_env_with_template(request, RACK_ENV_CONST)
# => {
#      "rack.url_scheme" => "http",
#      "SERVER_SOFTWARE" => "MyServer/1.0",
#      "REQUEST_METHOD" => "GET",
#      ...
#    }
```

The template is never modified and may be frozen. If a key is in both the template and the request, the request wins, but this isn't recommended.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jhawthorn/picohttp. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jhawthorn/picohttp/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Picohttp project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jhawthorn/picohttp/blob/main/CODE_OF_CONDUCT.md).
