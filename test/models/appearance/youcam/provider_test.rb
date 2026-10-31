require "test_helper"
require_relative "mapper_test"

class Appearance::Youcam::ProviderTest < ActiveSupport::TestCase
  BASE = "https://yce-api-01.makeupar.com"
  UPLOADS = %r{\Ahttps://yce-us\.s3-accelerate\.amazonaws\.com/}
  FULL_LOOK = Appearance::Youcam::MapperTest::FULL_LOOK

  setup do
    @provider = provider(keys: [ "test-key-a" ])
    @photo = jpeg(803, 1200)
    @puts = []
  end

  test "makeup round trip" do
    stub_balance("test-key-a", 1000)
    stub_register
    stub_uploads
    create = stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .with(body: { src_file_id: file_ids.first, version: "1.0", effects: live_body("makeup_vto_7effects_create.json")["effects"] })
      .to_return(body: response_body("makeup_vto_7effects_create.json").to_json)
    task_id = response_body("makeup_vto_7effects_create.json").dig("data", "task_id")
    stub_request(:get, "#{BASE}/s2s/v2.0/task/makeup-vto/#{task_id}").to_return(
      { body: response_body("makeup_vto_poll_running.json").to_json },
      { body: response_body("makeup_vto_7effects_poll_success.json").to_json })
    stub_request(:get, UPLOADS).to_return(body: file_fixture("youcam/makeup/m01_full_look.png").binread)

    job = @provider.start(:makeup, photo: @photo, effects: FULL_LOOK)
    assert_equal [ :makeup, task_id ], [ job.operation, job.external_id ]
    assert_requested create

    assert @provider.fetch(job).running?
    outcome = @provider.fetch(job)
    assert outcome.done?
    result = @provider.download(outcome, operation: :makeup)
    assert_equal "image/png", result.content_type
    stored = Vips::Image.new_from_buffer(result.bytes, "")
    assert_equal [ 800, 998 ], [ stored.width, stored.height ], "the result less its top 2 rows (EdgeTrim)"

    uploaded = Vips::Image.new_from_buffer(@puts.sole, "")
    assert_equal [ 680, 1016 ], [ uploaded.width, uploaded.height ]
    assert_equal 0, uploaded.width % 8
    assert_nil uploaded.get_fields.find { it.start_with?("exif") }
  end

  test "transfer round trip" do
    stub_balance("test-key-a", 1000)
    stub_register
    stub_uploads
    create = stub_request(:post, "#{BASE}/s2s/v2.0/task/mu-transfer")
      .with(body: { src_file_id: file_ids.first, ref_file_id: file_ids.second })
      .to_return(body: response_body("mu_transfer_create.json").to_json)
    task_id = response_body("mu_transfer_create.json").dig("data", "task_id")
    stub_request(:get, "#{BASE}/s2s/v2.0/task/mu-transfer/#{task_id}").to_return(
      { body: response_body("mu_transfer_poll_running.json").to_json },
      { body: response_body("mu_transfer_poll_success.json").to_json })
    stub_request(:get, UPLOADS).to_return(body: file_fixture("youcam/makeup/m03_mu_transfer.jpg").binread)

    job = @provider.start(:transfer, photo: @photo, reference: jpeg(1200, 900))
    assert_requested create
    assert_requested :post, "#{BASE}/s2s/v2.0/file", times: 1
    assert_equal 2, @puts.size

    assert @provider.fetch(job).running?
    result = @provider.download(@provider.fetch(job), operation: :transfer)
    assert_equal [ "image/jpeg", "result.jpg" ], [ result.content_type, result.filename ]
    assert_equal file_fixture("youcam/makeup/m03_mu_transfer.jpg").binread, result.bytes, "transfers stay as they come"
  end

  test "maps provider errors to reasons" do
    stub_balance("test-key-a", 1000)
    job = Appearance::Job.new(operation: :transfer, external_id: "t1", started_at: Time.current)

    stub_request(:get, "#{BASE}/s2s/v2.0/task/mu-transfer/t1").to_return(body: { status: 200, data: {
      error: "error_src_no_face", error_message: "No face", results: nil, task_status: "error" } }.to_json)
    outcome = @provider.fetch(job)
    assert_equal [ :failed, :no_face, :photo ], [ outcome.state, outcome.reason, outcome.about ]

    stub_request(:get, "#{BASE}/s2s/v2.0/task/mu-transfer/t1")
      .to_return(status: 400, body: response_body("../errors/invalid_task_id_400.json").to_json)
    assert_equal [ :failed, :provider_error ], @provider.fetch(job).then { [ it.state, it.reason ] }

    stub_request(:get, "#{BASE}/s2s/v2.0/task/mu-transfer/t1")
      .to_return(status: 500, body: { status: 500, error_code: "TaskTimeout" }.to_json)
    assert_equal [ :failed, :timeout ], @provider.fetch(job).then { [ it.state, it.reason ] }

    stub_register
    stub_uploads
    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .to_return(status: 400, body: { status: 400, error: "Not enough units", error_code: "CreditInsufficiency" }.to_json)
    error = assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }
    assert_equal :out_of_units, error.reason

    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto").to_return(status: 429, body: "")
    error = assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }
    assert_equal :rate_limited, error.reason

    error = assert_raises(Appearance::Error) { @provider.start(:makeup, photo: jpeg_bytes("not an image"), effects: FULL_LOOK) }
    assert_equal :bad_image, error.reason
  end

  test "picks next key when balance below floor" do
    provider = provider(keys: [ "test-key-a", "test-key-b" ])
    stub_balance("test-key-a", 120)
    stub_balance("test-key-b", 900)
    stub_register
    stub_uploads
    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .to_return(body: response_body("makeup_vto_7effects_create.json").to_json)

    provider.start(:makeup, photo: @photo, effects: FULL_LOOK)

    assert_requested :post, "#{BASE}/s2s/v2.0/task/makeup-vto", headers: { "Authorization" => "Bearer test-key-b" }
    assert_not_requested :post, "#{BASE}/s2s/v2.0/file", headers: { "Authorization" => "Bearer test-key-a" }
    assert_equal 900.0, provider.balance
  end

  test "a server or network error on create may have been charged, a refusal was not" do
    stub_balance("test-key-a", 1000)
    stub_register
    stub_uploads

    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto").to_return(status: 502, body: "")
    error = assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }
    assert_equal [ :provider_error, true ], [ error.reason, error.maybe_charged? ]

    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto").to_timeout
    assert_predicate assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }, :maybe_charged?

    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .to_return(status: 400, body: { status: 400, error_code: "CreditInsufficiency" }.to_json)
    assert_not_predicate assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }, :maybe_charged?
  end

  test "a create answer without a task id is an error" do
    stub_balance("test-key-a", 1000)
    stub_register
    stub_uploads
    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto").to_return(body: { status: 200, data: {} }.to_json)

    error = assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }
    assert_equal [ :provider_error, true ], [ error.reason, error.maybe_charged? ]
  end

  test "stops at the first key above the floor" do
    provider = provider(keys: [ "test-key-a", "test-key-b" ])
    stub_balance("test-key-a", 900)
    stub_balance("test-key-b", 900)
    stub_register
    stub_uploads
    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .to_return(body: response_body("makeup_vto_7effects_create.json").to_json)

    provider.start(:makeup, photo: @photo, effects: FULL_LOOK)
    assert_not_requested :get, "#{BASE}/s2s/v1.0/client/credit", headers: { "Authorization" => "Bearer test-key-b" }
  end

  test "refuses to start when every key is below the floor" do
    stub_balance("test-key-a", 149)
    error = assert_raises(Appearance::Error) { @provider.start(:makeup, photo: @photo, effects: FULL_LOOK) }
    assert_equal :out_of_units, error.reason
    assert_equal 149.0, @provider.balance
  end

  test "reads unit costs from the live price list and falls back to known prices" do
    skus = JSON.parse(file_fixture("youcam/account/feature_cost_all_skus.json").read)["skus"]
    stub_balance("test-key-a", 1000)
    stub_request(:get, "#{BASE}/s2s/v2.0/credit/feature-cost?page_size=20")
      .to_return(body: { status: 200, result: { skus: skus.first(20), next_token: "p2" } }.to_json)
    stub_request(:get, "#{BASE}/s2s/v2.0/credit/feature-cost?page_size=20&starting_token=p2")
      .to_return(body: { status: 200, result: { skus: skus.drop(20) } }.to_json)

    assert_equal 1.0, @provider.feature_cost(:makeup)
    assert_equal 2.0, @provider.feature_cost(:transfer)

    WebMock.reset!
    stub_balance("test-key-a", 1000)
    stub_request(:get, /feature-cost/).to_return(status: 401, body: "")
    assert_equal 2.0, provider(keys: [ "test-key-a" ]).feature_cost(:transfer)
  end

  test "is the provider when the environment asks for youcam" do
    provider = Appearance.build_provider("APPEARANCE_PROVIDER" => "youcam", "YOUCAM_API_KEYS" => "test-key-a, test-key-b")
    assert_kind_of Appearance::Youcam::Provider, provider
    assert_raises(ArgumentError) { Appearance.build_provider("APPEARANCE_PROVIDER" => "youcam") }
  end

  test "lists the public patterns for a category" do
    stub_request(:get, "https://plugins-media.makeupar.com/wcm-saas/patterns/eyeliner.json").to_return(body: [
      { category: "1 color", label: "Smoke4", thumbnail: "https://cdn.example.com/s.jpg", tags: [ { id: 1, name: "Smoke" } ], colorNum: 1 }
    ].to_json)

    assert_equal [ { name: "Smoke4", colours: 1, tags: [ "Smoke" ] } ], @provider.patterns(:eye_liner)
    assert_equal [], @provider.patterns(:foundation)
  end

  private
    def provider(keys:)
      client = Appearance::Youcam::Client.new(sleeper: ->(_seconds) { })
      Appearance::Youcam::Provider.new(keys:, floor: 150, client:)
    end

    def jpeg(width, height)
      jpeg_bytes(Vips::Image.black(width, height, bands: 3).add(90).cast(:uchar).jpegsave_buffer)
    end

    def jpeg_bytes(bytes)
      Appearance::Image.new(io: StringIO.new(bytes), filename: "photo.jpg", content_type: "image/jpeg")
    end

    def stub_balance(key, units)
      stub_request(:get, "#{BASE}/s2s/v1.0/client/credit").with(headers: { "Authorization" => "Bearer #{key}" })
        .to_return(body: { status: 200, results: [ { type: "ApiPaygToken", amount_dec: units, expiry: 4.weeks.from_now.to_i * 1000 } ] }.to_json)
    end

    # Answers like the API: one file id and presigned PUT per registered file, with that file's own size.
    def stub_register
      template = response_body("../file/register_multi.json")
      stub_request(:post, "#{BASE}/s2s/v2.0/file").to_return do |request|
        files = JSON.parse(request.body)["files"].each_with_index.map do |file, index|
          recorded = template.dig("data", "files", index)
          recorded.merge("file_name" => file["file_name"], "requests" => recorded["requests"].map do |put|
            put.merge("headers" => { "Content-Length" => file["file_size"].to_s, "Content-Type" => file["content_type"] })
          end)
        end
        { body: { status: 200, data: { files: } }.to_json }
      end
    end

    def stub_uploads
      stub_request(:put, UPLOADS).to_return { |request| @puts << request.body.b; { status: 200 } }
    end

    def file_ids
      response_body("../file/register_multi.json").dig("data", "files").map { it["file_id"] }
    end

    def response_body(name) = recorded(name).dig("response", "body")
    def live_body(name) = recorded(name).dig("request", "body")

    def recorded(name)
      JSON.parse(file_fixture("youcam/makeup/#{name}").read)
    end
end
