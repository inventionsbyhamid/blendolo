# Asks the provider how a running render's task is doing: at 3, 5, 8, 13 and 21 s after the start, then every 20 s,
# and gives up with :timeout 180 s after the start. On done it downloads the image into the render at once (result
# links expire). Anything unexpected (an error, a failed download) counts as "still running": the next poll asks again
# and fetches a fresh link, so no render spins forever. The webhook runs it once more with reschedule: false, so a
# webhook never starts a second chain.
class ProviderPollJob < ApplicationJob
  queue_as :youcam
  # The kit was deleted meanwhile.
  discard_on ActiveJob::DeserializationError

  SCHEDULE = [ 3, 5, 8, 13, 21 ].freeze
  EVERY = 20
  DEADLINE = 180

  def self.next_poll_at(started_at, now = Time.current)
    elapsed = now - started_at
    offset = SCHEDULE.find { |at| at > elapsed } || SCHEDULE.last + (((elapsed - SCHEDULE.last) / EVERY).floor + 1) * EVERY
    started_at + [ offset, DEADLINE + 1 ].min.seconds
  end

  def perform(render, reschedule: true)
    return unless render.running?
    return keep_waiting(render, reschedule) if render.external_id.blank?

    provider = Appearance.provider
    outcome = provider.fetch(render.provider_job)

    if outcome.done?
      render.finish_from!(outcome, provider)
    elsif outcome.failed?
      # The provider refunds engine errors; a task it timed out on may still be charged.
      render.fail_call!(outcome.reason, refund: outcome.reason != :timeout)
    else
      keep_waiting(render, reschedule)
    end
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { render_id: render.id })
    keep_waiting(render, reschedule)
  end

  private
    def keep_waiting(render, reschedule)
      if Time.current - render.started_at > DEADLINE
        render.fail_call!(:timeout, refund: false)
      elsif reschedule
        self.class.set(wait_until: self.class.next_poll_at(render.started_at)).perform_later(render)
      end
    end
end
