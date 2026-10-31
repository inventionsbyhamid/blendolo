require "test_helper"

class HardeningTest < ActionDispatch::IntegrationTest
  MEDIAPIPE = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1/".freeze
  MODEL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task".freeze

  test "csp and permissions policy" do
    get "/up"

    csp = response.headers["Content-Security-Policy"].split(";").map(&:strip).to_h { |d| [ d.split.first, d.split.drop(1) ] }
    assert_equal [ "'self'" ], csp["default-src"]
    assert_equal [ "'self'", "'wasm-unsafe-eval'", MEDIAPIPE ], csp["script-src"].grep_v(/\A'nonce-/)
    assert csp["script-src"].any? { it.start_with?("'nonce-") }
    assert csp["style-src"].any? { it.start_with?("'nonce-") }
    assert_equal [ "'self'", MEDIAPIPE, MODEL ], csp["connect-src"]
    assert_equal [ "'self'", "data:", "blob:" ], csp["img-src"]
    assert_equal [ "'none'" ], csp["object-src"]
    assert_equal [ "'none'" ], csp["frame-ancestors"]
    assert_equal [ "'self'", "https://accounts.google.com", "https://test.checkout.dodopayments.com",
      "https://checkout.dodopayments.com", "https://test.customer.dodopayments.com", "https://customer.dodopayments.com" ],
      csp["form-action"]
    assert_no_match(/unsafe-inline|unsafe-eval'|\*/, response.headers["Content-Security-Policy"].gsub("'wasm-unsafe-eval'", ""))

    policy = response.headers["Permissions-Policy"]
    assert_includes policy, "camera=(self)"
    assert_includes policy, "microphone=()"
    assert_includes policy, "geolocation=()"
  end

  test "tokens filtered from logs" do
    log = capture_log { get "/k/secret-kit-token-123/consent?token=secret-query-token&image=x" }
    started = log.lines.grep(/Started/).join

    assert_includes started, %(Started GET "/k/[FILTERED]/consent?token=[FILTERED]&image=[FILTERED]")
    assert_no_match(/secret-kit-token|secret-query-token/, started)

    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("token" => "a", "kit_token" => "b", "image" => "c", "reference" => "d", "sampled" => "e",
      "signed_id" => "f", "signed_blob_id" => "g", "encoded_key" => "h", "code" => "i", "state" => "j", "email" => "k")
    assert filtered.values.all?("[FILTERED]"), filtered.inspect
    assert Rails.application.config.filter_redirect.any? { it.match?("https://blendolo.dijmo.com/s/abc") }
    assert Rails.application.config.filter_redirect.any? { it.match?("https://blendolo.dijmo.com/rails/active_storage/blobs/proxy/x/a.jpg") }
  end

  test "a kit token in the sign in origin is filtered from logs" do
    log = capture_log { get "/sign_in?origin=/k/secret-kit-token-456/looks/red_lip" }

    assert_includes log, %(Started GET "/sign_in?origin=[FILTERED]")
    assert_no_match(/secret-kit-token/, log)
  end

  test "stored file links are filtered from logs" do
    log = capture_log { get "/rails/active_storage/blobs/proxy/secret-signed-id--abc/today.jpg" }

    assert_includes log, %(Started GET "/rails/active_storage/blobs/proxy/[FILTERED]")
    assert_no_match(/secret-signed-id/, log)
  end

  test "production keeps rescued errors and thruster's request log out of the logs" do
    assert_match(/^\s*config\.action_dispatch\.log_rescued_responses = false$/,
      Rails.root.join("config/environments/production.rb").read)
    assert_match(/^\s*LOG_REQUESTS="false"$/, Rails.root.join("Dockerfile").read)
  end

  test "thruster refuses request bodies over 15 MB" do
    assert_match(/MAX_REQUEST_BODY="15728640"/, Rails.root.join("Dockerfile").read)
  end

  test "libvips opens only its trusted loaders" do
    assert Vips.respond_to?(:block_untrusted)
    assert_path_exists Rails.root.join("config/initializers/vips.rb")
  end

  test "storage links expire after five minutes and our proxy links after an hour" do
    assert_equal 5.minutes, ActiveStorage.service_urls_expire_in
    assert_equal 1.hour, ActiveStorage.urls_expire_in
  end

  test "the privacy page names the services the capture page loads from, and the backups" do
    get "/privacy"

    assert_includes response.body, "jsDelivr"
    assert_includes response.body, "Google Cloud Storage"
    assert_match(/backups keep your answers and links, not your photos, for up to 2 days after that/, response.body)
    # The same two hosts the content security policy lets the capture page reach.
    assert_equal %w[cdn.jsdelivr.net storage.googleapis.com], [ MEDIAPIPE, MODEL ].map { URI(it).host }
  end

  test "direct uploads to storage are closed" do
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "x.jpg", byte_size: 3, checksum: "abc", content_type: "image/jpeg" } }, as: :json
    assert_response :not_found

    get "/rails/active_storage/direct_uploads"
    assert_response :not_found
  end

  test "the jobs page needs a password" do
    get "/jobs"
    assert_response :unauthorized

    get "/jobs", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("a", "b") }
    assert_response :unauthorized
  end

  private
    def capture_log
      io = StringIO.new
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
      io.string
    ensure
      Rails.logger = previous
    end
end
