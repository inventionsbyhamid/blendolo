require "test_helper"

class Ease::RoutineOrderTest < ActiveSupport::TestCase
  def test_order_precision_first_fixup_last
    # P: tinted moisturiser 0, smudged pencil 2, cream blush 0, mascara 2, wing 3, tinted balm 1
    steps = steps(%w[tinted_moisturiser_fingers smudged_pencil_liner cream_blush_fingers mascara_upper
                     liquid_liner_wing tinted_balm])

    ordered = Ease::RoutineOrder.order(steps).map(&:id)

    assert_equal %w[liquid_liner_wing smudged_pencil_liner mascara_upper
                    tinted_moisturiser_fingers cream_blush_fingers tinted_balm fixup], ordered
  end

  def test_fixup_moves_to_the_end_and_appears_once
    ordered = Ease::RoutineOrder.order(steps(%w[fixup tinted_balm fixup])).map(&:id)

    assert_equal %w[tinted_balm fixup], ordered
  end

  def test_empty_routine_is_just_the_fixup
    assert_equal %w[fixup], Ease::RoutineOrder.order([]).map(&:id)
  end

  private
    def steps(ids) = ids.map { Ease::StepCatalogue.fetch(it) }
end
