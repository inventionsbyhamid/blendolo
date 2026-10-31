ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Tests never reach the network (the appearance provider least of all): stub what a test needs. The local app server
# and browser driver for system tests stay reachable.
WebMock.disable_net_connect!(allow_localhost: true)
require_relative "support/lane_stand_ins"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
