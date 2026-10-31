require "test_helper"
require "support/copy_rules"
require "support/kit_helpers"
require "support/account_helpers"

class CopyLintTest < ActionDispatch::IntegrationTest
  include KitHelpers
  include AccountHelpers
  PUBLIC_PATHS = [ "/", "/privacy", "/accessibility", "/sources", "/guides", "/brands", "/sign_in", *PagesController::GUIDES.keys.map { |slug| "/guides/#{slug}" } ].freeze
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
        kit_shares_path(kit, audience: "helper"),
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

  test "no dashes or banned words on account pages and where previews are paid for" do
    user = make_user(credits: 3)
    kit = make_kit(tremor: 2)
    add_photo(kit, kind: :reference, sampled: { "lips" => "#A84452" })
    kit.update!(user:, label: "Mrs Patel")
    paid_pages = [ kit_look_path(kit, "red_lip"), kit_look_path(kit, "red_lip", level: 1), kit_signature_path(kit, liner: "winged", lips: "matte") ]

    paid_pages.each { |page| assert_page_copy page } # signed out
    sign_in_as(user)
    [ account_path, delete_account_path, kit_path(kit), *paid_pages ].each { |page| assert_page_copy page }
    Credits.debit!(user, Credits.balance(user), reason: :admin, source: nil)
    paid_pages.each { |page| assert_page_copy page } # out of credits
    sign_in_as(make_user)
    paid_pages.each { |page| assert_page_copy page } # another account's kit
    get root_path
    assert_page_copy root_path
  end

  # Sign in is needed to see looks on your own face, so no page may say there is no account.
  test "no page says there is no account" do
    PUBLIC_PATHS.each do |path|
      get path
      assert_no_match(/No account[.,]|No account and/, CopyRules.readable_copy(response.body), path)
    end
    get start_path
    assert_select ".lead", "No account needed to start. Your kit gets its own private link."
    get root_path
    assert_select ".cta__note", "Private. Try the examples with no account. Your first look on your face is free."
    get privacy_path
    assert_select "h2", "Google sign in"
    assert_match(/We store your name, email and Google id/, response.body)
    assert_no_match(/No account and/, Rails.root.join("README.md").read)
  end

  test "every preview failure message passes the copy rules" do
    RendersHelper::FAILURES.each_value do |message|
      assert_empty CopyRules.problems("<p>#{message}</p>"), message
    end
  end

  test "the words about credits pass the copy rules" do
    helper = ApplicationController.helpers
    [ CreditsHelper::SIGN_IN, CreditsHelper::OUT_OF_CREDITS, CreditsHelper::OTHER_ACCOUNT, helper.credits_cost_words(2, 14),
      helper.credits_balance_words(1), helper.credits_short_words(3, 1) ].each do |words|
      assert_empty CopyRules.problems("<p>#{words}</p>"), words
    end
  end

  test "the copy check finds dashes and banned words but allows Perfect Corp" do
    assert_equal [ "dash \"—\"" ], CopyRules.problems("<p>Wait — now</p>")
    assert_equal [ "banned word \"Despite\"" ], CopyRules.problems("<p>Despite it</p>")
    assert_equal [ "banned word \"the  shakes\"" ], CopyRules.problems("<img alt='the  shakes'>")
    assert_empty CopyRules.problems("<p>YouCam API from Perfect Corp. Healthy, treats nobody.</p>".sub("treats", "helps"))
  end

  private
    def assert_page_copy(page)
      get page
      assert_response :success, page
      assert_empty CopyRules.problems(response.body), "Copy problems on #{page}"
    end
end
