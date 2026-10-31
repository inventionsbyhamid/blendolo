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

  # Plays nothing: records each recording asked for (its path), each pause, and each line the phone's own voice reads.
  AUDIO_STUBS = <<~JS.freeze
    window.plays = []
    window.pauses = 0
    window.spoken = []
    HTMLAudioElement.prototype.play = function () {
      window.audio = this
      plays.push(new URL(this.src).pathname)
      return Promise.resolve()
    }
    HTMLAudioElement.prototype.pause = function () { pauses += 1 }
    window.speechSynthesis.speak = (utterance) => { spoken.push({ text: utterance.text, rate: utterance.rate }) }
  JS

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

  test "read it to me plays the card's recording once for a double tap, and a second tap stops it" do
    visit step_kit_routine_path(@kit, 1)
    execute_script AUDIO_STUBS
    execute_script "const b = [...document.querySelectorAll('button')].find((el) => el.textContent.includes('Read it to me')); b.click(); b.click()"
    HumanPace.last_click_at = HumanPace.now # the next tap waits out the repeat-tap window

    assert_selector "button[aria-pressed=true]", text: "Stop reading"
    # The browser's key for the card's words is the server's (Voice.key), so it plays that recording.
    assert_equal [ "/voice/#{Voice.key(Voice.card(@steps.first))}.mp3" ], evaluate_script("window.plays")
    assert_empty evaluate_script("window.spoken")

    click_on "Stop reading"
    assert_selector "button[aria-pressed=false]", text: "Read it to me"
    assert_equal 1, evaluate_script("window.pauses")
  end

  test "read it to me shows it's done when the recording ends" do
    visit step_kit_routine_path(@kit, 1)
    execute_script AUDIO_STUBS
    click_on "Read it to me"
    assert_selector "button[aria-pressed=true]", text: "Stop reading"

    execute_script "window.audio.dispatchEvent(new Event('ended'))"
    assert_selector "button[aria-pressed=false]", text: "Read it to me"
    assert_equal 0, evaluate_script("window.pauses")
  end

  test "read it to me uses the phone's own voice for a card without a recording" do
    visit step_kit_routine_path(@kit, 1)
    execute_script AUDIO_STUBS
    execute_script "document.querySelector('[data-controller~=speak]').dataset.speakVoicesValue = '{}'"
    click_on "Read it to me"

    assert_selector "button[aria-pressed=true]", text: "Stop reading"
    assert_empty evaluate_script("window.plays")
    spoken = evaluate_script("window.spoken")
    assert_equal 1, spoken.size
    assert_equal Voice.card(@steps.first), spoken.first["text"]
    assert_in_delta 0.9, spoken.first["rate"], 0.001
  end

  test "read it to me uses the phone's own voice when the recording won't play" do
    visit step_kit_routine_path(@kit, 1)
    execute_script AUDIO_STUBS
    execute_script "HTMLAudioElement.prototype.play = function () { plays.push('blocked'); return Promise.reject(new DOMException('No tap yet', 'NotAllowedError')) }"
    click_on "Read it to me"

    assert_equal [ "blocked" ], evaluate_script("window.plays")
    assert_equal [ Voice.card(@steps.first) ], evaluate_script("window.spoken.map((utterance) => utterance.text)")
    assert_selector "button[aria-pressed=true]", text: "Stop reading"
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

  test "a step card shows the easy preview zoomed to the step, labelled" do
    photo = @kit.photos.today.sole
    effects = LookForKit.find(@kit, "red_lip").easy_effects(photo).as_json
    @kit.renders.create!(photo:, look_key: "red_lip", kind: :easy, effects:, status: :done,
      result: { io: file_fixture("face.jpg").open, filename: "easy.jpg", content_type: "image/jpeg" })
    number = @steps.index { |step| step.category == "lip_color" } + 1

    page.current_window.resize_to(390, 844)
    visit step_kit_routine_path(@kit, number)

    assert_selector ".step-zoom--lips img.step-zoom__image"
    assert_selector ".honest", text: "Preview, not a promise"
    shot "step-card-zoom"
  end
end
