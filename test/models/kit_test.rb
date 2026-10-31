require "test_helper"

class KitTest < ActiveSupport::TestCase
  test "purge after uses retention" do
    freeze_time do
      kit = Kit.create!(retention_days: 7)
      assert_equal Time.current, kit.last_active_at
      assert_equal 7.days.from_now, kit.purge_after

      kit.update!(retention_days: 30)
      assert_equal 30.days.from_now, kit.purge_after
    end
  end

  test "retention defaults to 30 days and allows only 7 or 30" do
    assert_equal 30, Kit.new.retention_days
    assert_not Kit.new(retention_days: 14).valid?
  end

  test "touch activity pushes purge after forward" do
    kit = travel_to(10.days.ago) { Kit.create!(retention_days: 7) }

    freeze_time do
      kit.touch_activity!
      assert_equal Time.current, kit.reload.last_active_at
      assert_equal 7.days.from_now, kit.purge_after
    end
  end

  test "hand profile from answers" do
    kit = Kit.create!(tremor: 2, pinch: 1, one_hand: 2, fatigue: 0, near_vision: 1)
    assert_equal({ tremor: 2, pinch: 1, one_hand: 2, fatigue: 0, near_vision: 1 }, kit.hand_answers)

    unanswered = Kit.create!(tremor: 1)
    assert_equal({ tremor: 1, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0 }, unanswered.hand_answers)
  end

  test "hand answers and hands today stay within 0 to 2" do
    assert_not Kit.new(tremor: 3).valid?
    assert_not Kit.new(one_hand: -1).valid?
    assert_not Kit.new(hands_today: 3).valid?
    assert_equal 1, Kit.new.hands_today
  end

  test "gets a private token and a path" do
    kit = Kit.create!
    assert_equal 24, kit.token.length
    assert kit.self_use?
    assert_not kit.example?
    assert Kit.create!(path: :example, example_key: "rosa").example?
  end
end
