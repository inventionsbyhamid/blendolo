require "test_helper"

class ProviderThrottleTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @now = 1_000.0
    @slept = []
  end

  test "keeps 1.4 seconds between requests" do
    wait!
    assert_empty @slept

    @now += 0.5
    wait!
    assert_in_delta 0.9, @slept.sole, 0.001

    @now += 5
    wait!
    assert_equal 1, @slept.size
  end

  test "is wired in front of every live api request" do
    provider = Appearance.build_provider("APPEARANCE_PROVIDER" => "youcam", "YOUCAM_API_KEYS" => "test-key-a")
    hook = provider.instance_variable_get(:@client).instance_variable_get(:@before_request)
    assert_not_nil hook
  end

  private
    # The sleeper moves the clock on, as sleeping would.
    def wait!
      ProviderThrottle.wait!(cache: @cache, clock: -> { @now }, sleeper: ->(seconds) { @slept << seconds; @now += seconds })
    end
end
