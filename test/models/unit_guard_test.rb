require "test_helper"

class UnitGuardTest < ActiveSupport::TestCase
  setup do
    @kit = Kit.create!
    Appearance.provider = Appearance::FakeProvider.new(balance: 1000)
  end

  teardown { Appearance.provider = nil }

  test "lets a call through" do
    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :makeup)
  end

  test "kit cap blocks eleventh render" do
    10.times { |n| calls(n, operation: "makeup") }
    assert_equal :kit_cap, UnitGuard.check(kit: @kit, operation: :makeup)
    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :transfer)
    assert_equal :ok, UnitGuard.check(kit: Kit.create!, operation: :makeup)
  end

  test "a kit in an account pays with credits instead of the kit cap" do
    user = User.create!(provider: "google_oauth2", uid: "g-cap", email: "cap@example.com")
    @kit.update!(user:)
    10.times { |n| calls(n, operation: "makeup") }

    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :makeup)
  end

  test "kit cap allows two transfers and ignores refunded failures" do
    calls(1, operation: "transfer")
    calls(2, operation: "transfer", status: :failed, units: 0)
    assert_equal :ok, UnitGuard.check(kit: @kit, operation: :transfer)

    calls(3, operation: "transfer")
    assert_equal :kit_cap, UnitGuard.check(kit: @kit, operation: :transfer)
  end

  test "a failure that may have been charged counts towards the kit cap" do
    calls(1, operation: "transfer")
    calls(2, operation: "transfer", status: :failed, units: 2)
    assert_equal :kit_cap, UnitGuard.check(kit: @kit, operation: :transfer)
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

  test "caps and limits come from config and the environment" do
    assert_equal({ makeup: 10, transfer: 2 }, UnitGuard.per_kit)
    assert_equal 30, UnitGuard.daily_cap("YOUCAM_DAILY_UNIT_CAP" => "30")
    assert_equal 60, UnitGuard.daily_cap({})
    assert_equal 150, UnitGuard.floor({})
  end

  private
    def calls(n, operation:, status: :done, units: 1)
      ProviderCall.create!(kit: @kit, operation:, input_hash: "kit-#{n}", units:, status:)
    end
end
