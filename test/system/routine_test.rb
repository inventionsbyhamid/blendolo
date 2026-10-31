require "application_system_test_case"
require "support/kit_helpers"

class RoutineTest < ApplicationSystemTestCase
  include KitHelpers

  setup do
    @kit = make_kit(tremor: 2, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 1)
    @kit.update!(chosen_look_key: "red_lip", routine: RoutinePlan.from(LookForKit.find(@kit, "red_lip").easy_steps))
    @steps = RoutinePlan.steps(@kit)
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "routine cards in order with fixup last" do
    page.current_window.resize_to(390, 844)
    visit kit_routine_path(@kit)
    click_on "Start with step 1"

    seen = []
    @steps.each_with_index do |step, index|
      assert_selector ".step-header__count", text: "Step #{index + 1} of #{@steps.size}"
      seen << find("p.instruction").text
      shot "step-card" if index.zero?
      click_on(index == @steps.size - 1 ? "Done, all finished" : "Done, next step")
    end

    assert_equal @steps.map(&:instruction), seen
    assert_equal "fixup", @steps.last.id
    assert_current_path kit_path(@kit)
  end

  test "read it to me button present" do
    visit step_kit_routine_path(@kit, 1)
    execute_script <<~JS
      window.spoken = []
      window.speechSynthesis.speak = (utterance) => { window.spoken.push({ text: utterance.text, rate: utterance.rate }) }
    JS
    click_on "Read it to me"

    spoken = evaluate_script("window.spoken")
    assert_equal 1, spoken.size
    assert_includes spoken.first["text"], @steps.first.instruction
    assert_includes spoken.first["text"], "Why this is easier"
    assert_in_delta 0.9, spoken.first["rate"], 0.001
  end

  test "print view one card per page" do
    visit print_kit_routine_path(@kit)

    cards = all(".print-card")
    assert_equal @steps.size, cards.size
    cards.each do |card|
      assert_equal "page", card.evaluate_script("getComputedStyle(this).breakAfter")
      assert_operator card.evaluate_script("parseFloat(getComputedStyle(this).fontSize)"), :>=, 32
    end
    assert_selector ".print-card", text: @steps.last.instruction
    shot "print-cards"
  end

  test "a step card glows where the step goes when both previews exist" do
    photo = @kit.photos.today.sole
    effects = LookForKit.find(@kit, "red_lip").easy_effects(photo).as_json
    lips = effects.find { |effect| effect["category"] == "lip_color" }
    easy = @kit.renders.create!(photo:, look_key: "red_lip", kind: :easy, effects:, status: :done,
      result: { io: file_fixture("face_lips.jpg").open, filename: "easy.jpg", content_type: "image/jpeg" })
    @kit.renders.create!(photo:, look_key: "red_lip", kind: :step, effects: effects - [ lips ], status: :done,
      result: { io: file_fixture("face.jpg").open, filename: "step.jpg", content_type: "image/jpeg" })
    number = @steps.index { |step| step.category == "lip_color" } + 1

    page.current_window.resize_to(390, 844)
    visit step_kit_routine_path(@kit, number)

    assert_selector ".step-zoom--lips img.step-zoom__image"
    assert_selector "canvas.step-zoom__glow", visible: true, wait: 10
    glowing = evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector("canvas.step-zoom__glow")
        const data = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data
        let lit = 0
        for (let i = 3; i < data.length; i += 4) if (data[i] > 100) lit++
        return lit
      })()
    JS
    assert_operator glowing, :>, 0
    assert easy.persisted?
    shot "step-card-glow"
  end
end
