require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/cassettes"
  config.hook_into :webmock

  # Filter API keys from recordings
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }

  # Match on method and URI for Claude API (body can vary due to timestamps)
  config.default_cassette_options = {
    match_requests_on: [ :method, :uri ],
    record: :new_episodes,
    allow_playback_repeats: true
  }

  # Allow localhost connections for Rails tests
  config.ignore_localhost = true

  # Allow real HTTP connections when recording
  config.allow_http_connections_when_no_cassette = false
end

# Allow external connections during VCR recording
WebMock.allow_net_connect!
