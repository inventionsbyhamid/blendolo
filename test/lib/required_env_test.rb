require "test_helper"

class RequiredEnvTest < ActiveSupport::TestCase
  test "check raises naming blank variable" do
    error = assert_raises(RequiredEnv::Missing) do
      RequiredEnv.check!(%w[A B], env: { "A" => "x", "B" => "" })
    end

    assert_match(/\bB\b/, error.message)
  end

  test "check passes when every variable has a value" do
    assert_nothing_raised { RequiredEnv.check!(%w[A B], env: { "A" => "x", "B" => "y" }) }
  end

  test "check treats unset and whitespace as blank" do
    assert_raises(RequiredEnv::Missing) { RequiredEnv.check!(%w[A], env: {}) }
    assert_raises(RequiredEnv::Missing) { RequiredEnv.check!(%w[A], env: { "A" => "  " }) }
  end

  test "check names only the first blank variable" do
    error = assert_raises(RequiredEnv::Missing) do
      RequiredEnv.check!(%w[A B C], env: { "B" => "", "C" => "" })
    end

    assert_match(/\bA\b/, error.message)
    assert_no_match(/\b[BC]\b/, error.message)
  end

  test "check never shows a value" do
    error = assert_raises(RequiredEnv::Missing) do
      RequiredEnv.check!(%w[A B], env: { "A" => "s3cret-value", "B" => "" })
    end

    assert_not_includes error.message, "s3cret-value"
  end

  test "check accepts any one of a list of alternatives" do
    names = [ %w[RAILS_MASTER_KEY SECRET_KEY_BASE] ]

    assert_nothing_raised { RequiredEnv.check!(names, env: { "SECRET_KEY_BASE" => "x" }) }
    assert_nothing_raised { RequiredEnv.check!(names, env: { "RAILS_MASTER_KEY" => "x" }) }

    error = assert_raises(RequiredEnv::Missing) { RequiredEnv.check!(names, env: {}) }
    assert_includes error.message, "RAILS_MASTER_KEY or SECRET_KEY_BASE"
  end

  test "values outside the allowed set fail, naming the choices but not the value" do
    error = assert_raises(RequiredEnv::Invalid) do
      RequiredEnv.check_values!(env: { "APPEARANCE_PROVIDER" => "YouCam-typo", "BLENDOLO_PROCESS" => "web" })
    end
    assert_includes error.message, "APPEARANCE_PROVIDER must be youcam or fake"
    assert_not_includes error.message, "YouCam-typo"

    error = assert_raises(RequiredEnv::Invalid) { RequiredEnv.check_values!(env: { "BLENDOLO_PROCESS" => "worker" }) }
    assert_includes error.message, "BLENDOLO_PROCESS must be web or jobs"
  end

  test "allowed values and blanks pass the value check" do
    assert_nothing_raised do
      RequiredEnv.check_values!(env: { "APPEARANCE_PROVIDER" => " youcam ", "BLENDOLO_PROCESS" => "jobs" })
      RequiredEnv.check_values!(env: { "APPEARANCE_PROVIDER" => "fake" })
      RequiredEnv.check_values!(env: {})
    end
  end

  test "the jobs worker boots without the Google client" do
    names = RequiredEnv.production("BLENDOLO_PROCESS" => " jobs ").flatten

    assert_not_includes names, "GOOGLE_CLIENT_ID"
    assert_not_includes names, "GOOGLE_CLIENT_SECRET"
    assert_includes names, "R2_BUCKET"
  end

  test "production needs the Google client with Google sign in, the default" do
    default = RequiredEnv.production("APPEARANCE_PROVIDER" => "fake").flatten
    google = RequiredEnv.production("AUTH_PROVIDER" => " google ").flatten

    [ default, google ].each do |names|
      assert_includes names, "GOOGLE_CLIENT_ID"
      assert_includes names, "GOOGLE_CLIENT_SECRET"
    end

    web = RequiredEnv.production("BLENDOLO_PROCESS" => "web").flatten
    assert_includes web, "GOOGLE_CLIENT_ID"

    error = assert_raises(RequiredEnv::Invalid) { RequiredEnv.check_values!(env: { "AUTH_PROVIDER" => "gogle" }) }
    assert_includes error.message, "AUTH_PROVIDER must be google"
    assert_nothing_raised { RequiredEnv.check_values!(env: { "AUTH_PROVIDER" => "google" }) }
  end

  test "production needs the youcam variables only with the youcam provider" do
    fake = RequiredEnv.production("APPEARANCE_PROVIDER" => "fake").flatten
    youcam = RequiredEnv.production("APPEARANCE_PROVIDER" => "youcam").flatten

    assert_includes fake, "DB_HOST"
    assert_not_includes fake, "YOUCAM_API_KEYS"
    assert_includes youcam, "YOUCAM_API_KEYS"
    assert_includes youcam, "YOUCAM_DAILY_UNIT_CAP"
    assert_includes youcam, "YOUCAM_UNIT_FLOOR"
    assert_not_includes youcam, "YOUCAM_WEBHOOK_SECRET"
  end
end
