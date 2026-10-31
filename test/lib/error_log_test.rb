require "test_helper"

class ErrorLogTest < ActiveSupport::TestCase
  test "logs the error class and context, never the message" do
    log = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    ErrorLog.new.report(RuntimeError.new("https://bucket.example/x?X-Amz-Signature=secret"), handled: true,
      severity: :warning, context: { render_id: 42, job: ProviderPollJob.new, token: "kit-token" })

    assert_includes log.string, "Reported RuntimeError handled=true severity=warning ProviderPollJob render_id=42"
    assert_no_match(/secret|Signature|kit-token/, log.string)
  ensure
    Rails.logger = previous
  end

  test "production subscribes it" do
    assert_match(/Rails\.error\.subscribe\(ErrorLog\.new\)\s*\}\s*if Rails\.env\.production\?/,
      Rails.root.join("config/initializers/error_log.rb").read)
  end
end
