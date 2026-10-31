require "test_helper"

class Appearance::Youcam::ClientTest < ActiveSupport::TestCase
  BASE = "https://yce-api-01.makeupar.com"

  setup do
    @slept = []
    @throttled = 0
    @client = Appearance::Youcam::Client.new(sleeper: ->(seconds) { @slept << seconds }, before_request: -> { @throttled += 1 })
  end

  test "sends the key and a json content type, even on a get" do
    stub_request(:get, "#{BASE}/s2s/v1.0/client/credit")
      .with(headers: { "Authorization" => "Bearer test-key", "Content-Type" => "application/json" })
      .to_return(status: 200, body: { status: 200, results: [] }.to_json)

    assert_equal({ "status" => 200, "results" => [] }, @client.get("/s2s/v1.0/client/credit", key: "test-key"))
    assert_equal 1, @throttled
  end

  test "posts json" do
    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .with(body: { src_file_id: "f1" }.to_json, headers: { "Content-Type" => "application/json" })
      .to_return(status: 200, body: { data: { task_id: "t1" } }.to_json)

    assert_equal "t1", @client.post("/s2s/v2.0/task/makeup-vto", { src_file_id: "f1" }, key: "test-key").dig("data", "task_id")
  end

  test "retries a rate limit with backoff, then gives up" do
    stub_request(:get, "#{BASE}/s2s/v1.0/client/credit").to_return(status: 429, body: "")

    error = assert_raises(Appearance::Youcam::Client::HttpError) { @client.get("/s2s/v1.0/client/credit", key: "k") }
    assert_equal 429, error.status
    assert_requested :get, "#{BASE}/s2s/v1.0/client/credit", times: 3
    assert_equal [ 2, 4 ], @slept
    assert_equal 3, @throttled
  end

  test "retries server errors on reads but never repeats a task create" do
    stub_request(:get, "#{BASE}/s2s/v2.0/task/makeup-vto/t1")
      .to_return({ status: 502, body: "" }, { status: 200, body: { data: { task_status: "running" } }.to_json })
    assert_equal "running", @client.get("/s2s/v2.0/task/makeup-vto/t1", key: "k").dig("data", "task_status")

    stub_request(:post, "#{BASE}/s2s/v2.0/task/makeup-vto")
      .to_return(status: 500, body: { status: 500, error_code: "InternalError" }.to_json)
    error = assert_raises(Appearance::Youcam::Client::HttpError) { @client.post("/s2s/v2.0/task/makeup-vto", {}, key: "k") }
    assert_equal [ 500, "InternalError" ], [ error.status, error.code ]
    assert_requested :post, "#{BASE}/s2s/v2.0/task/makeup-vto", times: 1
  end

  test "retries network errors on reads" do
    stub_request(:get, "#{BASE}/s2s/v1.0/client/credit").to_timeout.then
      .to_return(status: 200, body: { results: [] }.to_json)
    assert_equal [], @client.get("/s2s/v1.0/client/credit", key: "k")["results"]

    stub_request(:get, "#{BASE}/s2s/v2.0/credit/feature-cost").to_raise(SocketError)
    error = assert_raises(Appearance::Youcam::Client::HttpError) { @client.get("/s2s/v2.0/credit/feature-cost", key: "k") }
    assert_equal 0, error.status
  end

  test "puts bytes with the exact headers it was given and downloads without the key or the throttle" do
    put = stub_request(:put, "https://uploads.example.com/f.jpg?X-Amz-Signature=abc")
      .with(body: "jpeg", headers: { "Content-Type" => "image/jpeg", "Content-Length" => "4" })
      .to_return(status: 200)
    stub_request(:get, "https://uploads.example.com/r.jpg?X-Amz-Signature=def").to_return(status: 200, body: "png")

    @client.put("https://uploads.example.com/f.jpg?X-Amz-Signature=abc", "jpeg",
      headers: { "Content-Type" => "image/jpeg", "Content-Length" => "4" })
    assert_equal "png", @client.download("https://uploads.example.com/r.jpg?X-Amz-Signature=def")

    assert_requested put
    assert_not_requested :get, "https://uploads.example.com/r.jpg?X-Amz-Signature=def", headers: { "Authorization" => /.*/ }
    assert_equal 0, @throttled
  end

  test "never puts the key in an error message" do
    stub_request(:get, "#{BASE}/s2s/v1.0/client/credit")
      .to_return(status: 401, body: { status: 401, error: "This API key is not recognized.", error_code: "InvalidApiKey" }.to_json)

    error = assert_raises(Appearance::Youcam::Client::HttpError) { @client.get("/s2s/v1.0/client/credit", key: "secret-key") }
    assert_equal "InvalidApiKey", error.code
    assert_no_match(/secret-key/, error.message)
  end
end
