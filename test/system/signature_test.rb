require "application_system_test_case"
require "support/kit_helpers"
require "support/face_results"
require "support/account_helpers"

class SignatureTest < ApplicationSystemTestCase
  include KitHelpers
  include AccountHelpers

  setup do
    @kit = make_kit(tremor: 2, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "signature flow with fake" do
    page.current_window.resize_to(390, 844)
    sign_in_in_browser(make_user(credits: 3))
    visit kit_signature_path(@kit)
    click_on "Choose an old photo"

    assert_selector "[data-capture-state=choose]", wait: 10
    assert_no_selector "button", text: "Take the photo"
    find("input[data-capture-target=choose]", visible: :all).attach_file(file_fixture("face.jpg"))
    assert_selector "[data-capture-state=review]", wait: 10
    click_on "Use this photo"

    assert_selector "h1", text: "Did you wear eyeliner?", wait: 10
    reference = @kit.photos.reference.sole
    # Colours the browser samples with MediaPipe (not loaded in tests).
    reference.update!(sampled: { "lips" => "#A84452", "lids" => "#9C8577", "cheeks" => "#E59A7A" })
    assert_selector ".step-header__count", text: "Step 2 of 3"
    click_on "Winged"
    assert_selector "h1", text: "Lips?"
    click_on "Matte"

    assert_selector "h1", text: "Your signature look, today"
    assert_selector ".spend__words", text: "Uses 3 credits. You have 5."
    click_on "Show it on my face"
    assert_no_selector ".spend"
    transfer = @kit.renders.transfer.sole
    easy = @kit.renders.easy.where(look_key: "signature").sole
    assert_equal reference, transfer.reference_photo
    assert_not_empty easy.effects

    [ transfer, easy ].each do |render|
      render.result.attach(io: file_fixture("face.jpg").open, filename: "#{render.kind}.jpg", content_type: "image/jpeg")
      render.update!(status: :done)
    end
    visit current_url
    within(".three-up") do
      assert_selector "img[alt='The old photo']"
      assert_selector "##{ActionView::RecordIdentifier.dom_id(transfer)} img.render__image"
      assert_selector "##{ActionView::RecordIdentifier.dom_id(easy)} img.render__image"
    end
    assert_text "Preview, not a promise"
    assert_text "Why it's easier:"
    shot "signature"

    click_on "Make this my routine"
    assert_selector "h1", text: "Your routine"
    assert_equal "signature", @kit.reload.chosen_look_key
  end

  test "reference with two faces rejected" do
    visit new_kit_photo_path(@kit, kind: "reference")
    assert_selector "[data-capture-state=choose]", wait: 10
    two_faces = FaceResults.result(FaceResults.face(centre: [ 0.3, 0.5 ], width: 0.3), FaceResults.face(centre: [ 0.7, 0.5 ], width: 0.3))
    # The capture checks as MediaPipe would answer for a photo of two people.
    execute_script <<~JS, two_faces
      const element = document.querySelector("[data-controller~=capture]")
      const capture = window.Stimulus.getControllerForElementAndIdentifier(element, "capture")
      capture.gate = { setOptions: async () => {}, detect: () => arguments[0] }
    JS

    find("input[data-capture-target=choose]", visible: :all).attach_file(file_fixture("face.jpg"))

    assert_selector "[data-capture-target=message]", text: "Try a photo of just you", wait: 10
    assert_no_selector "[data-capture-state=review]"
    assert_equal 0, @kit.photos.reference.count
  end
end
