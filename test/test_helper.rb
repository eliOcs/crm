require "simplecov"
SimpleCov.start "rails"

ENV["RAILS_ENV"] ||= "test"

# Set dummy Microsoft OAuth credentials for tests (if not already set)
ENV["MICROSOFT_CLIENT_ID"] ||= "test-client-id"
ENV["MICROSOFT_CLIENT_SECRET"] ||= "test-client-secret"

require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "support/vcr"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
