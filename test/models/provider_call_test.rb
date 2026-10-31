require "test_helper"

class ProviderCallTest < ActiveSupport::TestCase
  test "units spent on sums one day" do
    day = Date.new(2026, 11, 1)
    ProviderCall.create!(operation: "makeup", input_hash: "a", units: 1, day: day)
    ProviderCall.create!(operation: "transfer", input_hash: "b", units: 2.5, day: day)
    ProviderCall.create!(operation: "makeup", input_hash: "c", units: 4, day: day - 1)
    ProviderCall.create!(operation: "makeup", input_hash: "d", units: 8, day: day + 1)

    assert_equal 3.5, ProviderCall.units_spent_on(day)
    assert_equal 0, ProviderCall.units_spent_on(day + 2)
  end

  test "counts the day it was made on by default" do
    travel_to Time.utc(2026, 11, 1, 23, 59) do
      call = ProviderCall.create!(operation: "makeup", input_hash: "a", units: 1)
      assert_equal Date.new(2026, 11, 1), call.day
      assert call.pending?
    end
  end

  test "one call per operation and input" do
    ProviderCall.create!(operation: "makeup", input_hash: "a")
    assert ProviderCall.new(operation: "transfer", input_hash: "a").valid?
    assert_not ProviderCall.new(operation: "makeup", input_hash: "a").valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      ProviderCall.new(operation: "makeup", input_hash: "a").save!(validate: false)
    end
  end

  test "never keeps signed urls in the response" do
    signed = ProviderCall.new(operation: "makeup", input_hash: "a",
      response: { result: { url: "https://files.example.com/r.jpg?X-Amz-Signature=abc&Expires=1" } })
    assert_not signed.valid?

    assert ProviderCall.new(operation: "makeup", input_hash: "a", response: { result: { task_id: "t1" } }).valid?
  end
end
