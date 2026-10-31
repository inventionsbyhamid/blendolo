# Retention: deletes every kit whose last activity is older than its retention (7 or 30 days), files first, then the
# provider calls of deleted kits once they no longer count towards a daily cap (today and yesterday stay).
# Runs daily from config/recurring.yml. A kit that fails to delete is reported and retried the next day; it never
# stops the rest.
class PurgeExpiredKitsJob < ApplicationJob
  queue_as :default

  def perform
    Kit.where(purge_after: ..Time.current).find_each do |kit|
      Rails.error.handle(context: { kit_id: kit.id }) { kit.destroy_everything! }
    end
    ProviderCall.where(kit_id: nil).where(day: ...Date.yesterday).delete_all
  end
end
