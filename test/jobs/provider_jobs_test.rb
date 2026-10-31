require "test_helper"

class ProviderJobsTest < ActiveJob::TestCase
  EFFECTS = [ { "category" => "lip_color", "colour" => "#8E1F2F", "intensity" => 85, "texture" => "matte" } ].freeze

  setup do
    Appearance.provider = Appearance::FakeProvider.new
    @kit = Kit.create!
    @photo = @kit.photos.create!(source: "camera", image: jpeg("today.jpg"))
  end

  teardown { Appearance.provider = nil }

  test "duplicate request hits cache" do
    first = makeup_render
    second = makeup_render

    assert_enqueued_jobs 1, only: ProviderStartJob do
      assert_equal :queued, first.request!
      assert_equal :waiting, second.request!
    end
    assert_equal first.input_hash, second.input_hash
    assert_equal 1, ProviderCall.count
    assert_equal [ "makeup", 1.0, "pending" ], ProviderCall.sole.then { [ it.operation, it.units.to_f, it.status ] }
  end

  test "the cache key follows the photo bytes, the operation and the effects" do
    base = makeup_render.tap(&:request!).input_hash
    other_effects = makeup_render(effects: [ EFFECTS.first.merge("intensity" => 60) ]).tap(&:request!).input_hash
    other_photo = @kit.photos.create!(source: "camera", image: jpeg("other.jpg"))
    on_other_photo = makeup_render(photo: other_photo).tap(&:request!).input_hash
    same_bytes = @kit.photos.create!(source: "upload", image: jpeg("today.jpg"))
    on_same_bytes = makeup_render(photo: same_bytes).tap(&:request!).input_hash

    assert_equal 3, [ base, other_effects, on_other_photo ].uniq.size
    assert_equal base, on_same_bytes
    assert_equal Digest::SHA256.hexdigest("jpeg today.jpg"), @photo.reload.sha256
  end

  test "start job starts the task and schedules the first poll" do
    render = makeup_render.tap(&:request!)

    assert_enqueued_with(job: ProviderPollJob, args: [ render ]) do
      ProviderStartJob.perform_now(render)
    end
    render.reload
    assert render.running?
    assert_match(/\Afake-/, render.external_id)
    assert render.started_at.present?
    assert render.provider_call.running?
  end

  test "result image downloaded on done" do
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)

    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      ProviderPollJob.perform_now(render.reload)
    end

    render.reload
    assert render.done?
    assert_equal "image/png", render.result.content_type
    assert_equal file_fixture("youcam/makeup/m02_easy_look.png").binread, render.result.download
    call = render.provider_call
    assert call.done?
    assert_equal({ "content_type" => "image/png" }, call.response)
  end

  test "a done task finishes the renders that waited for it" do
    first = makeup_render.tap(&:request!)
    second = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(first)
    ProviderPollJob.perform_now(first.reload)

    assert second.reload.done?
    assert_equal first.result.download, second.result.download
  end

  test "retry reuses cached result" do
    first = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(first)
    ProviderPollJob.perform_now(first.reload)

    retry_render = makeup_render
    assert_no_enqueued_jobs only: [ ProviderStartJob, ProviderPollJob ] do
      assert_equal :cached, retry_render.request!
    end
    assert retry_render.reload.done?
    assert_equal first.result.download, retry_render.result.download
    assert_not_equal first.result.blob, retry_render.result.blob
    assert_equal 1, ProviderCall.count
  end

  test "a cached call whose result is gone calls again within caps" do
    first = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(first)
    ProviderPollJob.perform_now(first.reload)
    first.result.purge

    assert_enqueued_jobs 1, only: ProviderStartJob do
      assert_equal :queued, makeup_render.request!
    end
    assert_equal 2.0, ProviderCall.sole.units.to_f
  end

  test "keeps polling while the task runs" do
    Appearance.provider = Appearance::FakeProvider.new(ready_after: 60)
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)

    travel 4.seconds
    assert_enqueued_with(job: ProviderPollJob, at: render.reload.started_at + 5.seconds) do
      ProviderPollJob.perform_now(render)
    end
    assert render.reload.running?
  end

  test "poll gives up after deadline" do
    Appearance.provider = Appearance::FakeProvider.new(ready_after: 600)
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)

    travel 181.seconds
    assert_no_enqueued_jobs only: ProviderPollJob do
      ProviderPollJob.perform_now(render.reload)
    end
    assert render.reload.failed?
    assert_equal "timeout", render.failure_reason
    assert render.provider_call.failed?
  end

  test "an engine error fails the render, refunds the units and frees the kit's call" do
    Appearance.provider = Appearance::FakeProvider.new(fail_with: :no_face)
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)
    ProviderPollJob.perform_now(render.reload)

    assert render.reload.failed?
    assert_equal "no_face", render.failure_reason
    assert_equal [ "failed", 0.0 ], render.provider_call.then { [ it.status, it.units.to_f ] }
    assert_equal 0, UnitGuard.live_calls(@kit, :makeup)
  end

  test "a refused start fails the render without spending units" do
    Appearance.provider = Class.new(Appearance::FakeProvider) do
      def start(*) = raise(Appearance::Error.new(:rate_limited))
    end.new
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)

    assert_equal [ "failed", "rate_limited" ], render.reload.then { [ it.status, it.failure_reason ] }
    assert_equal 0.0, render.provider_call.units.to_f
  end

  test "a guard refusal fails the render at once" do
    kit = Kit.create!(path: :example)
    photo = kit.photos.create!(source: "example", image: jpeg("rosa.jpg"))
    render = kit.renders.create!(photo:, kind: :classic, effects: EFFECTS)

    assert_no_enqueued_jobs only: ProviderStartJob do
      assert_equal :example, render.request!
    end
    assert_equal [ "failed", "example" ], render.reload.then { [ it.status, it.failure_reason ] }
  end

  test "a transfer sends both photos" do
    reference = @kit.photos.create!(kind: :reference, source: "upload", image: jpeg("old.jpg"))
    render = @kit.renders.create!(photo: @photo, reference_photo: reference, kind: :transfer)
    render.request!

    assert_equal :transfer, render.operation
    assert_equal %i[photo reference], render.provider_inputs.keys
    assert_equal "jpeg old.jpg", render.provider_inputs[:reference].bytes
    ProviderStartJob.perform_now(render)
    ProviderPollJob.perform_now(render.reload)
    assert_equal "image/jpeg", render.reload.result.content_type
  end

  private
    def makeup_render(photo: @photo, effects: EFFECTS)
      @kit.renders.create!(photo:, kind: :easy, look_key: "red_lip", effects:)
    end

    def jpeg(filename)
      { io: StringIO.new("jpeg #{filename}"), filename:, content_type: "image/jpeg" }
    end
end
