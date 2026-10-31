require "test_helper"

class Appearance::FakeProviderTest < ActiveSupport::TestCase
  setup do
    @photo = Appearance::Image.new(io: StringIO.new("jpeg"), filename: "today.jpg", content_type: "image/jpeg")
    @effects = [ { category: "lip_color", colour: "#8E1F2F", intensity: 85, texture: "matte" } ]
  end

  teardown { WebMock.disable_net_connect!(allow_localhost: true) }

  test "fake provider never touches network" do
    WebMock.disable_net_connect!
    provider = Appearance::FakeProvider.new

    makeup = provider.start(:makeup, photo: @photo, effects: @effects)
    outcome = provider.fetch(makeup)
    assert outcome.done?
    result = provider.download(outcome)
    assert_equal "image/png", result.content_type
    assert_equal "result.png", result.filename

    transfer = provider.start(:transfer, photo: @photo, reference: @photo)
    result = provider.download(provider.fetch(transfer))
    assert_equal "image/jpeg", result.content_type

    assert_equal 1000.0, provider.balance
    assert_equal 1.0, provider.feature_cost(:makeup)
    assert_equal 2.0, provider.feature_cost(:transfer)
    assert_includes provider.patterns(:eye_liner).map { it[:name] }, "Smoke4"
  end

  test "a winged liner shows the full look and anything else the easy look" do
    provider = Appearance::FakeProvider.new
    winged = [ { category: "eye_liner", colour: "#111111", intensity: 90, pattern: "OpenWings2" } ]

    full = provider.download(provider.fetch(provider.start(:makeup, photo: @photo, effects: winged)))
    easy = provider.download(provider.fetch(provider.start(:makeup, photo: @photo, effects: @effects)))

    assert_equal file_fixture("youcam/makeup/m01_full_look.png").binread, full.io.read
    assert_equal file_fixture("youcam/makeup/m02_easy_look.png").binread, easy.io.read
  end

  test "can stay running for a while or fail with a reason" do
    slow = Appearance::FakeProvider.new(ready_after: 10)
    job = slow.start(:makeup, photo: @photo, effects: @effects)
    assert slow.fetch(job).running?
    travel(11.seconds) { assert slow.fetch(job).done? }

    failing = Appearance::FakeProvider.new(fail_with: :no_face)
    outcome = failing.fetch(failing.start(:transfer, photo: @photo, reference: @photo))
    assert outcome.failed?
    assert_equal :no_face, outcome.reason
  end

  test "rejects unknown operations and missing inputs" do
    provider = Appearance::FakeProvider.new
    assert_raises(ArgumentError) { provider.start(:hat, photo: @photo) }
    assert_raises(ArgumentError) { provider.start(:makeup, photo: @photo) }
    assert_raises(ArgumentError) { provider.start(:transfer, photo: @photo) }
  end

  test "picks the provider from the environment" do
    assert_kind_of Appearance::FakeProvider, Appearance.build_provider({})
    assert_kind_of Appearance::FakeProvider, Appearance.build_provider("APPEARANCE_PROVIDER" => "fake")
  end
end
