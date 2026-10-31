require "test_helper"

class Ease::RoutineOrderTest < ActiveSupport::TestCase
  setup do
    @default = Ease::HandProfile.new
  end

  def test_order_precision_first_fixup_last
    # Areas: face (P0), cheeks (P0), eyes (lid wash P1, mascara P2), lips (liquid lipstick P3), finish.
    steps = steps(%w[tinted_moisturiser_fingers cream_blush_fingers one_colour_lid_wash mascara_upper
                     liquid_matte_lipstick])

    ordered = Ease::RoutineOrder.order(steps).map(&:id)

    assert_equal %w[liquid_matte_lipstick one_colour_lid_wash mascara_upper
                    tinted_moisturiser_fingers cream_blush_fingers fixup], ordered
  end

  def test_eyes_layer_lid_then_liner_then_lashes
    look = Looks::Catalogue.fetch(:soft_smoky_evening)

    ordered = Ease::RoutineOrder.order(look.plan(@default)[:steps]).map(&:id)

    assert_equal %w[one_colour_lid_wash shadow_liner mascara_upper
                    tinted_moisturiser_fingers bronzer_big_brush tinted_balm fixup], ordered
  end

  def test_no_eye_step_ever_follows_a_higher_eye_layer
    looks = Looks::Catalogue.all
    profiles = [ @default, Ease::HandProfile.new(tremor: 2), Ease::HandProfile.new(pinch: 2, near_vision: 2) ]

    looks.product(profiles).each do |look, profile|
      [ look.ease_steps, look.plan(profile)[:steps] ].each do |steps|
        eyes = Ease::RoutineOrder.order(steps).select { it.area == "eyes" }

        assert_equal eyes.map(&:layer_index).sort, eyes.map(&:layer_index), "#{look.key} #{profile.to_h}"
      end
    end
  end

  def test_finish_is_fixup_then_setting_spray
    look = Looks::Catalogue.fetch(:wedding_guest)

    ordered = Ease::RoutineOrder.order(look.plan(@default)[:steps]).map(&:id)

    assert_equal %w[fixup setting_spray], ordered.last(2)
    assert_equal %w[wash_and_smudged_lash_line mascara_upper], ordered.first(2), "the precise eye area first"
  end

  def test_loose_powder_goes_over_the_cream_products
    look = Looks::Catalogue.fetch(:wedding_guest)

    ordered = Ease::RoutineOrder.order(look.plan(@default)[:steps]).map(&:id)

    assert_equal %w[wash_and_smudged_lash_line mascara_upper tinted_moisturiser_fingers stick_concealer_finger
                    bronzer_stick_sponge cream_highlighter_finger cream_blush_fingers kabuki_powder tinted_brow_gel
                    tinted_balm fixup setting_spray], ordered
  end

  def test_areas_without_precision_follow_the_usual_layer_order
    steps = steps(%w[tinted_balm tinted_brow_gel cream_blush_fingers tinted_moisturiser_fingers])

    assert_equal %w[tinted_moisturiser_fingers cream_blush_fingers tinted_brow_gel tinted_balm fixup],
                 Ease::RoutineOrder.order(steps).map(&:id)
  end

  def test_fixup_moves_to_the_finish_and_appears_once
    assert_equal %w[tinted_balm fixup], Ease::RoutineOrder.order(steps(%w[fixup tinted_balm fixup])).map(&:id)
  end

  def test_empty_routine_is_just_the_fixup
    assert_equal %w[fixup], Ease::RoutineOrder.order([]).map(&:id)
  end

  private
    def steps(ids) = ids.map { Ease::StepCatalogue.fetch(it) }
end
