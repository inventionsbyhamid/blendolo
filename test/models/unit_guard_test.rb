require "test_helper"

class UnitGuardTest < ActiveSupport::TestCase
  setup do
    @kit = Kit.create!
    Appearance.provider = Appearance::FakeProvider.new(balance: 1000)
  end

  teardown { Appearance.provider = nil }

  test "lets a call through, however many the kit made: kits pay with credits" do
    10.times { |n| calls(n, operation: "makeup") }
    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :makeup)
  end

  test "daily cap counts every kit's units today" do
    ProviderCall.create!(operation: "makeup", input_hash: "a", units: 59, day: Date.current)
    ProviderCall.create!(operation: "makeup", input_hash: "b", units: 40, day: Date.yesterday)
    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :makeup)
    assert_equal :daily_cap, UnitGuard.check(kit: @kit, operation: :transfer)
  end

  test "floor blocks when balance low" do
    Appearance.provider = Appearance::FakeProvider.new(balance: 150)
    assert_equal :floor, UnitGuard.check(kit: @kit, operation: :makeup)

    Appearance.provider = Appearance::FakeProvider.new(balance: 151)
    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :makeup)
  end

  test "example kits never call the provider" do
    assert_equal :example, UnitGuard.check(kit: Kit.create!(path: :example), operation: :makeup)
  end

  test "limits come from the environment" do
    assert_equal 30, UnitGuard.daily_cap("YOUCAM_DAILY_UNIT_CAP" => "30")
    assert_equal 60, UnitGuard.daily_cap({})
    assert_equal 150, UnitGuard.floor({})
  end

  private
    def calls(n, operation:, status: :done, units: 1)
      ProviderCall.create!(kit: @kit, operation:, input_hash: "kit-#{n}", units:, status:)
    end
end
