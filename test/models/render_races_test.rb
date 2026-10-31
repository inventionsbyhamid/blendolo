require "test_helper"
require "support/account_helpers"

# Races and half-way failures around a paid render: a stale second request never moves a running render back, a
# lost insert race waits, our own error before the provider call refunds, and a failure is all or nothing.
class RenderRacesTest < ActiveJob::TestCase
  include AccountHelpers

  EFFECTS = [ { "category" => "lip_color", "colour" => "#8E1F2F", "intensity" => 85, "texture" => "matte" } ].freeze

  setup do
    Appearance.provider = Appearance::FakeProvider.new
    @user = make_user(credits: 5)
    @kit = Kit.create!(user: @user)
    @photo = @kit.photos.create!(source: "camera", image: { io: StringIO.new("jpeg today"), filename: "today.jpg", content_type: "image/jpeg" })
  end

  teardown { Appearance.provider = nil }

  test "a second Try again that loaded the render before it started never moves it back from running" do
    render = makeup_render.tap { it.update!(status: :failed, failure_reason: "timeout") }
    stale = Render.find(render.id)
    assert_equal :queued, render.request!
    ProviderStartJob.perform_now(render)
    assert render.reload.running?

    assert_equal :waiting, stale.request!

    assert render.reload.running?
    assert_equal 4, Credits.balance(@user), "paid once"
  end

  test "losing the call row race to another request waits instead of failing" do
    taken = ProviderCall.new(operation: "makeup", input_hash: "x").tap { it.errors.add(:input_hash, :taken) }
    raising = ->(*) { raise ActiveRecord::RecordInvalid, taken }

    replacing(ProviderCall.singleton_class, :create!, raising) do
      assert_equal :waiting, makeup_render.request!
    end
    assert_equal 5, Credits.balance(@user)
  end

  test "our own error before anything is sent to the provider gives the credit back" do
    render = makeup_render.tap(&:request!)
    assert_equal 4, Credits.balance(@user)

    replacing(Render, :provider_inputs, -> { raise ActiveStorage::FileNotFoundError }) do
      ProviderStartJob.perform_now(render)
    end

    assert_equal "provider_error", render.reload.failure_reason
    assert_equal 5, Credits.balance(@user)
  end

  test "a failure is all or nothing: a refund that can't be written leaves the render as it was" do
    render = makeup_render.tap(&:request!)
    render.claim_start!

    replacing(Credits.singleton_class, :refund_render!, ->(*) { raise ActiveRecord::Deadlocked }) do
      assert_raises(ActiveRecord::Deadlocked) { render.fail_call!(:no_face, refund: true) }
    end

    assert render.reload.running?
    assert_equal 4, Credits.balance(@user)
    render.fail_call!(:no_face, refund: true)
    assert_equal [ "failed", 5 ], [ render.reload.status, Credits.balance(@user) ]
  end

  private
    # Puts body in place of klass#method_name while the block runs (minitest 6 has no stub).
    def replacing(klass, method_name, body)
      patch = Module.new { define_method(method_name, &body) }
      klass.prepend(patch)
      yield
    ensure
      patch.send(:remove_method, method_name)
    end

    def makeup_render
      @kit.renders.create!(photo: @photo, kind: :easy, look_key: "red_lip", effects: EFFECTS)
    end
end
