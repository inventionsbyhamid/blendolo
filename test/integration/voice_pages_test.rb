require "test_helper"
require "support/kit_helpers"

# The step card and photo pages hand voice/player.js the recordings of their own words.
class VoicePagesTest < ActionDispatch::IntegrationTest
  include KitHelpers

  test "a step card offers the recording of its words as the page reads them" do
    kit = make_kit(tremor: 2, pinch: 1, one_hand: 0, fatigue: 1, near_vision: 0)
    post kit_routine_path(kit), params: { look_key: "red_lip" }
    steps = RoutinePlan.steps(kit.reload)

    steps.each_with_index do |step, index|
      get step_kit_routine_path(kit, index + 1)
      assert_response :success
      page = Nokogiri::HTML(response.body)
      # The words of the paragraphs "Read it to me" reads, joined as speak_controller.js joins them.
      words = Voice.join(page.css("[data-speak-target=text]").map(&:text))
      assert_equal Voice.card(step), words, step.id

      voices = JSON.parse(page.at_css("[data-controller~=speak]")["data-speak-voices-value"])
      assert_equal({ Voice.key(words) => Voice.manifest.dig(Voice.key(words), "audio") }, voices, step.id)
    end
  end

  test "an optional step's card offers the recording with the optional line" do
    kit = make_kit(tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
    post kit_routine_path(kit), params: { look_key: Looks::Catalogue.all.find { |look| look.steps.any?(&:optional) }.key }
    steps = RoutinePlan.steps(kit.reload)
    number = steps.index(&:optional?) + 1

    get step_kit_routine_path(kit, number)
    page = Nokogiri::HTML(response.body)
    words = Voice.join(page.css("[data-speak-target=text]").map(&:text))
    assert words.start_with?("Optional. Skip it on shaky days.")
    assert_equal [ Voice.key(words) ], JSON.parse(page.at_css("[data-controller~=speak]")["data-speak-voices-value"]).keys
  end

  test "the photo page offers the recordings of everything it says, its prompt in the person's words" do
    [ :self_use, :helper ].each do |path|
      kit = make_kit(path:, photo: false, tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
      get new_kit_photo_path(kit, kind: "reference")
      assert_response :success
      capture = Nokogiri::HTML(response.body).at_css("[data-controller~=capture]")

      voices = JSON.parse(capture["data-capture-voices-value"])
      prompt = capture["data-capture-choose-prompt-value"]
      assert_includes voices.keys, Voice.key(prompt), "#{path}: #{prompt}"
      assert_equal Voice.capture_lines.map { |text| Voice.key(text) }.sort, voices.keys.sort
    end
  end
end
