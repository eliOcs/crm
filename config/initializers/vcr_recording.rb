# VCR Recording for Development
#
# This initializer enables VCR recording in development to capture real API
# interactions for creating test fixtures. Use this when you need to record
# new cassettes for external API calls (Microsoft Graph, Anthropic, etc.)
#
# == Quick Start
#
#   1. Start server with recording enabled:
#      VCR_RECORD=1 bin/dev-tunnel
#
#   2. Add VcrRecording.record wrapper to the code you want to capture:
#      VcrRecording.record("my_feature") { call_external_api }
#
#   3. Trigger the code path (e.g., send an email to trigger webhook)
#
#   4. Find cassettes in test/cassettes/dev_recording/
#
#   5. Rename and move cassettes to test/cassettes/ for use in tests
#
#   6. Remove the VcrRecording.record wrapper from production code
#
# == Example: Recording a new API interaction
#
#   # Step 1: Add wrapper to job/service (temporarily)
#   def perform
#     if defined?(VcrRecording) && VcrRecording.enabled?
#       VcrRecording.record("my_new_feature") do
#         do_api_call
#       end
#     else
#       do_api_call
#     end
#   end
#
#   # Step 2: Run with VCR_RECORD=1 and trigger the code
#   # Step 3: Cassette saved to test/cassettes/dev_recording/my_new_feature_<timestamp>.yml
#   # Step 4: Copy to test/cassettes/my_new_feature.yml
#   # Step 5: Use in test:
#   #   VCR.use_cassette("my_new_feature") { perform_enqueued_jobs }
#   # Step 6: Remove the wrapper from production code
#
# == Cassette Location
#
#   Recorded: test/cassettes/dev_recording/<name>_<timestamp>.yml
#   For tests: test/cassettes/<name>.yml
#
# == Filtered Data
#
#   The following sensitive data is automatically filtered:
#   - ANTHROPIC_API_KEY
#   - MICROSOFT_CLIENT_ID
#   - MICROSOFT_CLIENT_SECRET
#   - Microsoft access_token and refresh_token in responses

if Rails.env.development? && ENV["VCR_RECORD"].present?
  require "vcr"
  require "webmock"

  WebMock.enable!
  WebMock.allow_net_connect!

  VCR.configure do |config|
    config.cassette_library_dir = Rails.root.join("test/cassettes")
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

    config.default_cassette_options = {
      match_requests_on: [ :method, :uri ],
      record: :new_episodes,
      allow_playback_repeats: true
    }

    config.ignore_localhost = true
    config.allow_http_connections_when_no_cassette = true
  end

  # Helper module for VCR recording in development
  module VcrRecording
    class << self
      def enabled?
        ENV["VCR_RECORD"].present?
      end

      # Record a cassette with a unique name based on context
      def record(name, &block)
        return yield unless enabled?

        cassette_name = "dev_recording/#{name}_#{Time.current.strftime('%Y%m%d_%H%M%S')}"
        Rails.logger.info "[VCR] Recording cassette: #{cassette_name}"

        result = VCR.use_cassette(cassette_name, record: :new_episodes) do
          yield
        end

        Rails.logger.info "[VCR] Saved cassette: test/cassettes/#{cassette_name}.yml"
        result
      end
    end
  end

  Rails.logger.info "[VCR] Recording enabled - cassettes will be saved to test/cassettes/dev_recording/"
end
