require "test_helper"
require "support/copy_rules"

class CopyLintTest < ActionDispatch::IntegrationTest
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

  test "the copy check finds dashes and banned words but allows Perfect Corp" do
    assert_equal [ "dash \"—\"" ], CopyRules.problems("<p>Wait — now</p>")
    assert_equal [ "banned word \"Despite\"" ], CopyRules.problems("<p>Despite it</p>")
    assert_equal [ "banned word \"the  shakes\"" ], CopyRules.problems("<img alt='the  shakes'>")
    assert_empty CopyRules.problems("<p>YouCam API from Perfect Corp. Healthy, treats nobody.</p>".sub("treats", "helps"))
  end
end
