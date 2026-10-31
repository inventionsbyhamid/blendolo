require "test_helper"

class Ease::HandProfileTest < ActiveSupport::TestCase
  def test_default_weights_are_1_for_step_dimensions_and_0_for_opening
    assert_equal({ P: 1, E: 1, G: 1, H: 1, T: 1, F: 1, O: 0 }, weights)
    assert_predicate Ease::HandProfile.new, :default?
  end

  def test_tremor_raises_precision_near_the_eye_and_forgiveness
    assert_equal({ P: 3, E: 2, G: 1, H: 1, T: 1, F: 2, O: 0 }, weights(tremor: 2))
    assert_equal({ P: 2, E: 1.5, G: 1, H: 1, T: 1, F: 1.5, O: 0 }, weights(tremor: 1))
  end

  def test_pinch_pain_raises_grip_and_opening_and_sometimes_adds_half_the_extra
    assert_equal({ P: 1, E: 1, G: 3, H: 1.5, T: 1.5, F: 1, O: 3 }, weights(pinch: 2))
    assert_equal({ P: 1, E: 1, G: 2, H: 1.25, T: 1.25, F: 1, O: 1.5 }, weights(pinch: 1))
  end

  def test_one_hand_either_side_raises_hands_opening_and_grip
    expected = { P: 1, E: 1, G: 1.5, H: 3, T: 1, F: 1, O: 3 }

    assert_equal expected, weights(one_hand: 1)
    assert_equal expected, weights(one_hand: 2)
  end

  def test_fatigue_raises_time_and_sets_the_long_look_penalty
    assert_equal 3, weights(fatigue: 2)[:T]
    assert_equal 2, weights(fatigue: 1)[:T]
    assert_equal [ 0, 2, 4 ], (0..2).map { Ease::HandProfile.new(fatigue: it).fatigue_penalty }
  end

  def test_near_vision_raises_precision_and_near_the_eye
    assert_equal({ P: 2, E: 2, G: 1, H: 1, T: 1, F: 1, O: 0 }, weights(near_vision: 2))
    assert_equal({ P: 1.5, E: 1.5, G: 1, H: 1, T: 1, F: 1, O: 0 }, weights(near_vision: 1))
  end

  def test_when_two_answers_set_the_same_weight_the_larger_wins
    assert_equal({ P: 3, E: 2, G: 3, H: 3, T: 3, F: 2, O: 3 },
                 weights(tremor: 2, pinch: 2, one_hand: 1, fatigue: 2, near_vision: 1))
    # pinch asks for H 1.5 and G 3, one hand for H 3 and G 1.5
    assert_equal 3, weights(pinch: 2, one_hand: 2)[:H]
    assert_equal 3, weights(pinch: 2, one_hand: 2)[:G]
  end

  def test_answers_can_be_strings_and_must_be_0_1_or_2
    assert_equal 2, Ease::HandProfile.new(tremor: "2").tremor
    assert_raises(ArgumentError) { Ease::HandProfile.new(tremor: 3) }
    assert_raises(ArgumentError) { Ease::HandProfile.new(pinch: nil) }
    assert_raises(ArgumentError) { Ease::HandProfile.new(fatigue: "a lot") }
  end

  private
    def weights(**answers) = Ease::HandProfile.new(**answers).weights
end
