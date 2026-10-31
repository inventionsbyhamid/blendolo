require "test_helper"
require "support/account_helpers"

# Live previews on a person's own face are paid with credits, inside Render#request!: after the unit guard and the
# cache, before the start job; refunded when the provider refuses for sure, kept when it may have charged.
class RenderCreditsTest < ActiveJob::TestCase
  include AccountHelpers

  EFFECTS = [ { "category" => "lip_color", "colour" => "#8E1F2F", "intensity" => 85, "texture" => "matte" } ].freeze

  setup do
    Appearance.provider = Appearance::FakeProvider.new
    @user = make_user(credits: 5)
    @kit = Kit.create!(user: @user)
    @photo = @kit.photos.create!(source: "camera", image: jpeg("today.jpg"))
  end

  teardown { Appearance.provider = nil }

  test "a makeup render costs 1 credit and a transfer 2, taken before the start job" do
    assert_enqueued_jobs 1, only: ProviderStartJob do
      assert_equal :queued, makeup_render.request!
    end
    assert_equal 4, Credits.balance(@user)

    reference = @kit.photos.create!(kind: :reference, source: "upload", image: jpeg("old.jpg"))
    transfer = @kit.renders.create!(photo: @photo, reference_photo: reference, kind: :transfer)
    assert_equal :queued, transfer.request!
    assert_equal 2, Credits.balance(@user)
    assert_equal [ [ "render", -1 ], [ "transfer", -2 ] ],
      @user.credit_entries.where(reason: %w[render transfer]).order(:id).map { [ it.reason, it.delta ] }
    assert_equal "render:#{transfer.id}", @user.credit_entries.order(:id).last.source
  end

  test "a double tap is debited once" do
    first, second = makeup_render, makeup_render

    assert_enqueued_jobs 1, only: ProviderStartJob do
      assert_equal :queued, first.request!
      assert_equal :waiting, second.request!
      assert_equal :waiting, first.request!
    end
    assert_equal 4, Credits.balance(@user)
  end

  test "a cache hit costs no credit" do
    first = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(first)
    ProviderPollJob.perform_now(first.reload)
    assert first.reload.done?

    assert_equal :cached, makeup_render.request!
    assert_equal 4, Credits.balance(@user)
  end

  test "a definite refusal from the provider gives the credit back, once" do
    Appearance.provider = Appearance::FakeProvider.new(fail_with: :no_face)
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)
    ProviderPollJob.perform_now(render.reload)
    render.reload.fail_call!(:no_face, refund: true)

    assert_equal "no_face", render.reload.failure_reason
    assert_equal 5, Credits.balance(@user)
    assert_equal 1, @user.credit_entries.where(reason: "refund").count
  end

  test "a refused start gives the credit back" do
    Appearance.provider = provider_raising(Appearance::Error.new(:rate_limited))
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)

    assert_equal "rate_limited", render.reload.failure_reason
    assert_equal 5, Credits.balance(@user)
  end

  test "a failure that may have been charged keeps the credit" do
    Appearance.provider = provider_raising(Appearance::Error.new(:provider_error, maybe_charged: true))
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)
    assert_equal 4, Credits.balance(@user)

    Appearance.provider = Appearance::FakeProvider.new(ready_after: 600)
    slow = makeup_render(effects: [ EFFECTS.first.merge("intensity" => 40) ]).tap(&:request!)
    ProviderStartJob.perform_now(slow)
    travel(ProviderPollJob::DEADLINE + 5) { ProviderPollJob.perform_now(slow.reload) }
    assert_equal "timeout", slow.reload.failure_reason
    assert_equal 3, Credits.balance(@user)
  end

  test "asking again after a refund pays again, and a second refund gives back only that" do
    Appearance.provider = provider_raising(Appearance::Error.new(:rate_limited))
    render = makeup_render.tap(&:request!)
    ProviderStartJob.perform_now(render)
    assert_equal 5, Credits.balance(@user)

    Appearance.provider = Appearance::FakeProvider.new
    assert_equal :queued, render.reload.request!
    assert_equal 4, Credits.balance(@user)
    render.reload.fail_call!(:no_face, refund: true)
    render.reload.fail_call!(:no_face, refund: true)
    assert_equal 5, Credits.balance(@user)
  end

  test "not enough credits refuses before any provider call" do
    Credits.debit!(@user, 4, reason: :admin, source: nil)
    reference = @kit.photos.create!(kind: :reference, source: "upload", image: jpeg("old.jpg"))
    transfer = @kit.renders.create!(photo: @photo, reference_photo: reference, kind: :transfer)
    Appearance.provider = provider_raising(RuntimeError.new("the provider must not be called"))

    assert_no_enqueued_jobs only: ProviderStartJob do
      assert_equal :no_credits, transfer.request!
    end
    assert_equal [ "failed", "no_credits" ], transfer.reload.then { [ it.status, it.failure_reason ] }
    assert_equal 0, ProviderCall.count
    assert_equal 1, Credits.balance(@user)
    assert transfer.awaiting_payment?
  end

  test "a kit in no account asks for a sign in and spends nothing" do
    guest = Kit.create!
    render = guest.renders.create!(photo: guest.photos.create!(source: "camera", image: jpeg("guest.jpg")), kind: :easy, effects: EFFECTS)

    assert_no_enqueued_jobs only: ProviderStartJob do
      assert_equal :sign_in, render.request!
    end
    assert_equal "sign_in", render.reload.failure_reason
    assert_equal 0, ProviderCall.count
  end

  test "a render refused for credits is asked again by the next tap once there are credits" do
    Credits.debit!(@user, 5, reason: :admin, source: nil)
    render = Previews.for(@kit, @photo, "red_lip", :easy, EFFECTS)
    assert render.reload.awaiting_payment?

    Credits.grant!(@user, 16, reason: :pack_purchase, source: "pay_1")
    assert_enqueued_jobs 1, only: ProviderStartJob do
      assert_equal render, Previews.for(@kit, @photo, "red_lip", :easy, EFFECTS)
      Previews.for(@kit, @photo, "red_lip", :easy, EFFECTS)
    end
    assert render.reload.pending?
    assert_equal 15, Credits.balance(@user)
  end
end

# Requests at the same moment, each on its own connection: the row lock on the user keeps the balance at zero or more.
class RenderCreditsConcurrencyTest < ActiveSupport::TestCase
  include AccountHelpers
  include ActiveJob::TestHelper

  self.use_transactional_tests = false

  setup { Appearance.provider = Appearance::FakeProvider.new }

  teardown do
    Appearance.provider = nil
    Kit.where(user: @user).find_each(&:destroy_everything!) if @user
    ProviderCall.delete_all
    @user&.destroy!
  end

  test "concurrent requests never take the balance below zero" do
    @user = make_user(credits: 2)
    kit = Kit.create!(user: @user)
    photo = kit.photos.create!(source: "camera", image: { io: StringIO.new("jpeg race"), filename: "race.jpg", content_type: "image/jpeg" })
    # Four at once: the connection pool has five, and this thread holds one.
    renders = Array.new(4) do |n|
      kit.renders.create!(photo:, kind: :easy, look_key: "red_lip",
        effects: [ { "category" => "lip_color", "colour" => "#8E1F2F", "intensity" => 10 + n } ])
    end
    photo.content_sha256!

    gate = Concurrent::CountDownLatch.new(1)
    threads = renders.map do |render|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.wait
          Render.find(render.id).request!
        end
      end
    end
    gate.count_down
    verdicts = ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }

    assert_equal 2, verdicts.count(:queued), verdicts.inspect
    assert_equal 2, verdicts.count(:no_credits), verdicts.inspect
    assert_equal 0, Credits.balance(@user)
    assert_equal 2, ProviderCall.count
    assert @user.credit_entries.all? { it.balance_after >= 0 }
  end
end

class RenderCreditsTest
  private
    def makeup_render(effects: EFFECTS)
      @kit.renders.create!(photo: @photo, kind: :easy, look_key: "red_lip", effects:)
    end

    def provider_raising(error)
      Class.new(Appearance::FakeProvider) { define_method(:start) { |*| raise error } }.new
    end

    def jpeg(filename)
      { io: StringIO.new("jpeg #{filename}"), filename:, content_type: "image/jpeg" }
    end
end
