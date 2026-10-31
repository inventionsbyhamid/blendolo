require "test_helper"
require "support/kit_helpers"

class ExamplesTest < ActionDispatch::IntegrationTest
  include KitHelpers

  setup { KitHelpers::CountRequests.count = 0 }

  test "an example that isn't seeded yet says coming soon" do
    get example_path("rosa")
    assert_response :success
    assert_select ".empty__title", "Example coming soon"

    assert_no_difference -> { Kit.count } do
      post start_example_path("rosa")
    end
    assert_redirected_to example_path("rosa")
  end

  test "example kit never calls provider" do
    template = seed_example("rosa")
    stored = template.renders.create!(photo: template.photos.first, look_key: "red_lip", kind: :classic, status: :done,
      effects: LookForKit.find(template, "red_lip").classic_effects(template.photos.first).as_json,
      result: { io: file_fixture("face.jpg").open, filename: "classic.jpg", content_type: "image/jpeg" })

    post start_example_path("rosa")
    kit = Kit.order(:id).last
    assert_redirected_to kit_path(kit)
    assert kit.example?
    assert_equal 2, kit.tremor

    get kit_look_path(kit, "red_lip")
    assert_response :success

    assert_equal 0, KitHelpers::CountRequests.count
    assert_equal 0, ProviderCall.count
    classic = kit.renders.classic.sole
    assert classic.done?
    assert_equal stored.result.blob, classic.result.blob
    assert_equal "example", kit.renders.easy.sole.failure_reason
  end

  test "each visitor gets their own copy" do
    seed_example("june")

    post start_example_path("june")
    post start_example_path("june")
    copies = Kit.example.where(example_key: "june").order(:id).drop(1)
    assert_equal 2, copies.size
    assert_not_equal copies.first.token, copies.last.token
  end

  test "deleting a copy keeps the example person's photo" do
    template = seed_example("amara")
    post start_example_path("amara")
    copy = Kit.order(:id).last

    delete kit_path(copy)
    assert template.photos.first.reload.image.attached?
    assert template.photos.first.image.blob.service.exist?(template.photos.first.image.blob.key)
  end

  private
    def seed_example(key)
      Kit.create!(path: :example, example_key: key, consented_at: Time.current, tremor: 2, pinch: 0, one_hand: 0,
        fatigue: 1, near_vision: 1).tap { |kit| add_photo(kit) }
    end
end
