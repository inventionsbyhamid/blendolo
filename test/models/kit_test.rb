require "test_helper"

class KitTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "purge after uses retention" do
    freeze_time do
      kit = Kit.create!(retention_days: 7)
      assert_equal Time.current, kit.last_active_at
      assert_equal 7.days.from_now, kit.purge_after

      kit.update!(retention_days: 30)
      assert_equal 30.days.from_now, kit.purge_after
    end
  end

  test "retention defaults to 30 days and allows only 7 or 30" do
    assert_equal 30, Kit.new.retention_days
    assert_not Kit.new(retention_days: 14).valid?
  end

  test "touch activity pushes purge after forward" do
    kit = travel_to(10.days.ago) { Kit.create!(retention_days: 7) }

    freeze_time do
      kit.touch_activity!
      assert_equal Time.current, kit.reload.last_active_at
      assert_equal 7.days.from_now, kit.purge_after
    end
  end

  test "destroy everything removes attachments and rows" do
    kit = Kit.create!
    today = kit.photos.create!(source: "camera", image: real_jpeg("today.jpg"))
    reference = kit.photos.create!(kind: :reference, source: "upload", image: jpeg("old.jpg"))
    kit.renders.create!(photo: today, kind: :classic, status: :done, result: jpeg("classic.jpg"))
    kit.renders.create!(photo: today, reference_photo: reference, kind: :transfer)
    kit.shares.create!(audience: :helper)
    call = ProviderCall.create!(kit: kit, operation: "makeup", input_hash: "a", units: 1, response: { "content_type" => "image/png" })
    other = Kit.create!
    other.photos.create!(source: "camera", image: jpeg("other.jpg"))
    variant = today.image.variant(resize_to_limit: [ 8, 8 ]).processed.image.blob

    keys = kit.photos.map { it.image.key } + kit.renders.filter_map { it.result.key if it.result.attached? } << variant.key
    assert_equal 4, keys.size
    assert keys.all? { ActiveStorage::Blob.service.exist?(it) }

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      kit.destroy_everything!
    end

    assert_not Kit.exists?(kit.id)
    assert_equal 0, Photo.where(kit_id: kit.id).count + Render.where(kit_id: kit.id).count + Share.where(kit_id: kit.id).count
    assert keys.none? { ActiveStorage::Blob.service.exist?(it) }
    assert_equal [ other.photos.sole.image.blob ], ActiveStorage::Blob.where(key: keys + [ other.photos.sole.image.key ]).to_a
    assert_not ActiveStorage::VariantRecord.exists?(blob_id: today.image.blob.id)
    assert_nil call.reload.kit_id
    assert_equal({}, call.response)
    assert_equal 1, ProviderCall.units_spent_on(call.day)
  end

  test "hand profile from answers" do
    kit = Kit.create!(tremor: 2, pinch: 1, one_hand: 2, fatigue: 0, near_vision: 1)
    assert_equal({ tremor: 2, pinch: 1, one_hand: 2, fatigue: 0, near_vision: 1 }, kit.hand_answers)

    unanswered = Kit.create!(tremor: 1)
    assert_equal({ tremor: 1, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0 }, unanswered.hand_answers)
  end

  test "hand answers and hands today stay within 0 to 2" do
    assert_not Kit.new(tremor: 3).valid?
    assert_not Kit.new(one_hand: -1).valid?
    assert_not Kit.new(hands_today: 3).valid?
    assert_equal 1, Kit.new.hands_today
  end

  test "gets a private token and a path" do
    kit = Kit.create!
    assert_equal 24, kit.token.length
    assert kit.self_use?
    assert_not kit.example?
    assert Kit.create!(path: :example, example_key: "rosa").example?
  end

  private
    def jpeg(filename)
      { io: StringIO.new("jpeg #{filename}"), filename: filename, content_type: "image/jpeg" }
    end

    # A decodable image, for variants.
    def real_jpeg(filename)
      { io: StringIO.new(Vips::Image.black(16, 16, bands: 3).jpegsave_buffer), filename:, content_type: "image/jpeg" }
    end
end
