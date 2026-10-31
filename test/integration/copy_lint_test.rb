require "test_helper"
require "support/copy_rules"
require "support/kit_helpers"

class CopyLintTest < ActionDispatch::IntegrationTest
  include KitHelpers
  PUBLIC_PATHS = [ "/", "/privacy", "/accessibility", "/sources", "/guides", *PagesController::GUIDES.keys.map { |slug| "/guides/#{slug}" } ].freeze
  STATIC_PAGES = %w[400.html 404.html 406-unsupported-browser.html 422.html 500.html offline.html].freeze

  test "no dashes or banned words in rendered pages" do
    PUBLIC_PATHS.each do |path|
      get path
      assert_response :success
      assert_empty CopyRules.problems(response.body), "Copy problems on #{path}"
    end

    STATIC_PAGES.each do |file|
      assert_empty CopyRules.problems(Rails.root.join("public", file).read), "Copy problems in public/#{file}"
    end
  end

  test "no dashes or banned words on kit pages, one per step" do
    [ :self_use, :helper ].each do |path|
      kit = make_kit(path:, tremor: 2, pinch: 1, one_hand: 0, fatigue: 1, near_vision: 0)
      post kit_routine_path(kit), params: { look_key: "red_lip" }
      share = kit.shares.create!(audience: :helper, scope: :routine_and_photos)
      reference = add_photo(kit, kind: :reference, sampled: { "lips" => "#A84452", "cheeks" => "#E59A7A" })
      kit.renders.create!(photo: kit.photos.today.first, look_key: "red_lip", kind: :easy, status: :failed, failure_reason: "timeout")

      paths = [ start_path, examples_path, example_path("rosa"), kit_path(kit), delete_kit_path(kit), kit_consent_path(kit),
        *(1..5).map { |number| kit_hand_path(kit, number) }, new_kit_photo_path(kit), new_kit_photo_path(kit, kind: "reference"),
        kit_looks_path(kit), kit_look_path(kit, "red_lip"), kit_look_path(kit, "red_lip", level: 1), kit_routine_path(kit),
        step_kit_routine_path(kit, 1), step_kit_routine_path(kit, kit.reload.routine.size), print_kit_routine_path(kit), kit_signature_path(kit),
        kit_signature_path(kit, liner: "winged", lips: "matte"), kit_shopping_path(kit), kit_shares_path(kit),
        public_share_path(share.token) ]
      paths.each do |page|
        get page
        assert_response :success, page
        assert_empty CopyRules.problems(response.body), "Copy problems on #{page}"
      end
      assert reference.persisted?
    end

    example = Examples.kit_for("rosa")
    [ kit_path(example), kit_looks_path(example), kit_look_path(example, "red_lip"), kit_signature_path(example),
      kit_routine_path(example) ].each do |page|
      get page
      assert_response :success, page
      assert_empty CopyRules.problems(response.body), "Copy problems on #{page}"
    end
  end

  test "every preview failure message passes the copy rules" do
    RendersHelper::FAILURES.each_value do |message|
      assert_empty CopyRules.problems("<p>#{message}</p>"), message
    end
  end

  test "the copy check finds dashes and banned words but allows Perfect Corp" do
    assert_equal [ "dash \"—\"" ], CopyRules.problems("<p>Wait — now</p>")
    assert_equal [ "banned word \"Despite\"" ], CopyRules.problems("<p>Despite it</p>")
    assert_equal [ "banned word \"the  shakes\"" ], CopyRules.problems("<img alt='the  shakes'>")
    assert_empty CopyRules.problems("<p>YouCam API from Perfect Corp. Healthy, treats nobody.</p>".sub("treats", "helps"))
  end
end
