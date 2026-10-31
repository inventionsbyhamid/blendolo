# Starts the provider task for a render that ProviderTracked#request! queued, then schedules the first poll.
class ProviderStartJob < ApplicationJob
  queue_as :youcam

  def perform(render)
    return unless render.pending?

    job = Appearance.provider.start(render.operation, render.provider_inputs)
    render.update!(status: :running, external_id: job.external_id, started_at: job.started_at)
    render.provider_call&.update!(status: :running)
    ProviderPollJob.set(wait_until: ProviderPollJob.next_poll_at(render.started_at)).perform_later(render)
  rescue Appearance::Error => error
    render.fail_call!(error.reason, refund: true)
  end
end
