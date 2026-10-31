# Keeps at least 1.4 s between any two requests to the provider's API, across every process: the API allows 250
# requests per 5 minutes per IP and per key, and 1.4 s keeps us at about 214. A Postgres advisory lock makes callers
# take turns; the time of the last request lives in Rails.cache (Solid Cache in production, shared by web and jobs).
module ProviderThrottle
  INTERVAL = 1.4
  LOCK_ID = 7_301_142 # any number no other advisory lock in the app uses
  KEY = "provider-throttle/last-request-at"

  module_function

  def wait!(interval: INTERVAL, cache: Rails.cache, clock: -> { Time.now.to_f }, sleeper: ->(seconds) { sleep(seconds) })
    ActiveRecord::Base.with_connection do |connection|
      connection.execute("SELECT pg_advisory_lock(#{LOCK_ID})")
      begin
        last = cache.read(KEY)
        gap = last && last + interval - clock.call
        sleeper.call(gap) if gap&.positive?
        cache.write(KEY, clock.call, expires_in: 1.minute)
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{LOCK_ID})")
      end
    end
  end
end
