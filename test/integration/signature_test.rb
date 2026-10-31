require "test_helper"
require "support/kit_helpers"
require "support/account_helpers"

class SignatureFlowTest < ActionDispatch::IntegrationTest
  include KitHelpers
  include AccountHelpers

  setup do
    @user = make_user(credits: 10)
    sign_in_as(@user)
    @kit = make_kit(tremor: 2)
    add_photo(@kit, kind: :reference, sampled: { "lips" => "#A84452", "lids" => "#9C8577", "cheeks" => "#E59A7A" })
  end

  test "one question per screen, then a transfer and an easy render made once" do
    get kit_signature_path(@kit)
    assert_select "h1", /Did you wear eyeliner/
    get kit_signature_path(@kit, liner: "winged")
    assert_select "h1", "Lips?"
    # Answering goes to the results page, which shows the price before anything is spent.
    assert_select "a[href=?]", kit_signature_path(@kit, liner: "winged", lips: "matte"), text: /Matte/
    get kit_signature_path(@kit, liner: "winged", lips: "matte")
    assert_select ".spend__words", "Uses 3 credits. You have 12."

    assert_difference -> { @kit.renders.count }, 2 do
      2.times { post kit_signature_path(@kit), params: { liner: "winged", lips: "matte" } }
    end
    assert_redirected_to kit_signature_path(@kit, liner: "winged", lips: "matte")
    assert_equal %w[easy transfer], @kit.renders.map(&:kind).sort

    follow_redirect!
    assert_select ".three-up figure", 3
    assert_equal 9, Credits.balance(@user)
  end

  test "two credits short of the signature look, neither part is made" do
    Credits.debit!(@user, 10, reason: :admin, source: nil)
    assert_equal 2, Credits.balance(@user)

    post kit_signature_path(@kit), params: { liner: "winged", lips: "matte" }

    assert_redirected_to kit_signature_path(@kit, liner: "winged", lips: "matte")
    assert_empty @kit.renders
    assert_equal 2, Credits.balance(@user)
  end

  test "signed out, the signature look says what it costs and what the free credits cover" do
    delete sign_out_path
    kit = make_kit(tremor: 2)
    add_photo(kit, kind: :reference, sampled: { "lips" => "#A84452" })

    get kit_signature_path(kit, liner: "winged", lips: "matte")

    assert_select ".spend__words", "Sign in to see your signature look on your face. It uses 3 credits. Your 2 free credits cover one look on your face."
  end

  test "answers we don't offer go back to the start" do
    post kit_signature_path(@kit), params: { liner: "glitter", lips: "matte" }
    assert_redirected_to kit_signature_path(@kit)
    assert_equal 0, @kit.renders.count
  end

  test "no old photo yet asks for one" do
    kit = make_kit
    get kit_signature_path(kit)
    assert_select "a[href=?]", new_kit_photo_path(kit, kind: "reference"), text: /Choose an old photo/
  end

  test "the results page from history makes no renders" do
    assert_no_difference -> { Render.count } do
      get kit_signature_path(@kit, liner: "winged", lips: "matte")
    end
    assert_select ".three-up figure", 3
    assert_select "form[action=?] button", kit_signature_path(@kit), text: /Show it on my face/
    assert_select "form[data-controller=autostart]", count: 0

    get kit_signature_path(@kit, liner: "winged", lips: "matte"), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_response :no_content
  end
end
