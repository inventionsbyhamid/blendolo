require "test_helper"

class Webhooks::YoucamControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "whsec_#{Base64.strict_encode64('test webhook secret, not a real one')}".freeze

  setup do
    kit = Kit.create!
    photo = kit.photos.create!(source: "camera", image: { io: StringIO.new("jpeg"), filename: "t.jpg", content_type: "image/jpeg" })
    @tracked = kit.renders.create!(photo:, kind: :classic, status: :running, external_id: "task-1", started_at: Time.current)
    @previous_secret = ENV["YOUCAM_WEBHOOK_SECRET"]
    ENV["YOUCAM_WEBHOOK_SECRET"] = SECRET
  end

  teardown { ENV["YOUCAM_WEBHOOK_SECRET"] = @previous_secret }

  test "webhook rejects bad signature" do
    assert_no_enqueued_jobs do
      deliver(payload("task-1"), signature: "v1,#{Base64.strict_encode64('x' * 32)}")
    end
    assert_response :unauthorized

    assert_no_enqueued_jobs do
      deliver(payload("task-1"), timestamp: 10.minutes.ago.to_i)
    end
    assert_response :unauthorized

    assert_no_enqueued_jobs { deliver(payload("task-1"), signature: "") }
    assert_response :unauthorized
  end

  test "a signed webhook polls the render at once, without starting a second poll chain" do
    assert_enqueued_with(job: ProviderPollJob, args: [ @tracked, { reschedule: false } ]) do
      deliver(payload("task-1"))
    end
    assert_response :ok
  end

  test "accepts any of several signatures" do
    body = payload("task-1")
    good = signature_for(body, "msg_1", Time.current.to_i)
    assert_enqueued_jobs 1, only: ProviderPollJob do
      deliver(body, signature: "v1,#{Base64.strict_encode64('y' * 32)} #{good}")
    end
  end

  test "unknown or finished tasks are acknowledged and ignored" do
    assert_no_enqueued_jobs { deliver(payload("someone-elses-task")) }
    assert_response :ok

    @tracked.update!(status: :done)
    assert_no_enqueued_jobs { deliver(payload("task-1")) }
    assert_response :ok
  end

  test "without a secret it takes unsigned calls" do
    ENV["YOUCAM_WEBHOOK_SECRET"] = nil
    assert_enqueued_jobs 1, only: ProviderPollJob do
      post "/webhooks/youcam", params: payload("task-1"), headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
  end

  private
    def payload(task_id)
      { created_at: Time.current.to_i, data: { task_id:, task_status: "success" } }.to_json
    end

    def deliver(body, id: "msg_1", timestamp: Time.current.to_i, signature: signature_for(body, id, timestamp))
      post "/webhooks/youcam", params: body, headers: {
        "Content-Type" => "application/json", "webhook-id" => id, "webhook-timestamp" => timestamp.to_s,
        "webhook-signature" => signature
      }
    end

    def signature_for(body, id, timestamp)
      key = Base64.decode64(SECRET.delete_prefix("whsec_"))
      "v1,#{Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', key, "#{id}.#{timestamp}.#{body}"))}"
    end
end
