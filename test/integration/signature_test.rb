require "test_helper"
require "support/kit_helpers"

class SignatureFlowTest < ActionDispatch::IntegrationTest
  include KitHelpers

  setup do
    @kit = make_kit(tremor: 2)
    add_photo(@kit, kind: :reference, sampled: { "lips" => "#A84452", "lids" => "#9C8577", "cheeks" => "#E59A7A" })
  end

  test "one question per screen, then a transfer and an easy render made once" do
    get kit_signature_path(@kit)
    assert_select "h1", /Did you wear eyeliner/
    get kit_signature_path(@kit, liner: "winged")
    assert_select "h1", "Lips?"

    assert_difference -> { @kit.renders.count }, 2 do
      2.times { post kit_signature_path(@kit), params: { liner: "winged", lips: "matte" } }
    end
    assert_redirected_to kit_signature_path(@kit, liner: "winged", lips: "matte")
    assert_equal %w[easy transfer], @kit.renders.map(&:kind).sort

    follow_redirect!
    assert_select ".three-up figure", 3
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
end
