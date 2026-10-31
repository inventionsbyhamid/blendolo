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
    expired_month.photos.create!(source: "camera",
      image: { io: StringIO.new("jpeg"), filename: "today.jpg", content_type: "image/jpeg" })

    PurgeExpiredKitsJob.perform_now

    assert_equal [ came_back, recent_month, recent_week ].map(&:id).sort, Kit.pluck(:id).sort
    assert_not Kit.exists?(expired_month.id)
    assert_not Kit.exists?(expired_week.id)
    assert_equal 0, ActiveStorage::Blob.count
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
