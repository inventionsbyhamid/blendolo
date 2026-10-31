require "test_helper"
require "fugit"

class PurgeExpiredKitsJobTest < ActiveJob::TestCase
  test "purge job deletes only expired kits" do
    expired_month = travel_to(31.days.ago) { Kit.create!(retention_days: 30) }
    expired_week = travel_to(8.days.ago) { Kit.create!(retention_days: 7) }
    recent_week = travel_to(6.days.ago) { Kit.create!(retention_days: 7) }
    recent_month = travel_to(8.days.ago) { Kit.create!(retention_days: 30) }
    came_back = travel_to(40.days.ago) { Kit.create!(retention_days: 30) }
    came_back.touch_activity!
    photo = expired_month.photos.create!(source: "camera",
      image: { io: StringIO.new("jpeg"), filename: "today.jpg", content_type: "image/jpeg" })
    blob = photo.image.blob

    PurgeExpiredKitsJob.perform_now

    kits = [ expired_month, expired_week, recent_week, recent_month, came_back ]
    assert_equal [ recent_week, recent_month, came_back ].map(&:id), Kit.where(id: kits).order(:id).ids
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "keeps provider calls of deleted kits two days for the daily cap, then deletes them" do
    kit = Kit.create!
    owned = ProviderCall.create!(kit:, operation: "makeup", input_hash: "owned", day: 5.days.ago.to_date)
    today = ProviderCall.create!(operation: "makeup", input_hash: "today", day: Date.current)
    yesterday = ProviderCall.create!(operation: "makeup", input_hash: "yesterday", day: Date.yesterday)
    old = ProviderCall.create!(operation: "makeup", input_hash: "old", day: 2.days.ago.to_date)

    PurgeExpiredKitsJob.perform_now

    assert_equal [ owned, today, yesterday ].map(&:id).sort, ProviderCall.where(id: [ owned, today, yesterday, old ]).ids.sort
  end

  test "runs every day at 3 am UTC in production" do
    entry = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
      .dig("production", "purge_expired_kits")

    assert_equal "PurgeExpiredKitsJob", entry["class"]
    schedule = Fugit.parse_cron(entry["schedule"])
    assert_equal Time.utc(2026, 11, 2, 3), schedule.next_time(Time.utc(2026, 11, 1, 12)).to_t.utc
    assert_equal Time.utc(2026, 11, 3, 3), schedule.next_time(Time.utc(2026, 11, 2, 3)).to_t.utc
  end
end
