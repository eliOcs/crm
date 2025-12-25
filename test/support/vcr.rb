require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/cassettes"
  config.hook_into :webmock

  # Filter API keys from recordings
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<MICROSOFT_CLIENT_ID>") { ENV["MICROSOFT_CLIENT_ID"] }
  config.filter_sensitive_data("<MICROSOFT_CLIENT_SECRET>") { ENV["MICROSOFT_CLIENT_SECRET"] }

  # Filter Microsoft tokens from response bodies
  config.before_record do |interaction|
    if interaction.response.body.include?("access_token")
      interaction.response.body.gsub!(/"access_token":"[^"]+"/, '"access_token":"<FILTERED>"')
      interaction.response.body.gsub!(/"refresh_token":"[^"]+"/, '"refresh_token":"<FILTERED>"')
    end
  end

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
