# Starts the provider task for a render that ProviderTracked#request! queued, then schedules the first poll.
# Only the job that claims the render (pending to running) calls the provider. Any failure fails the render: a
# definite refusal is refunded; anything else (a server or network error, our own error) keeps its units, because
# the provider may have started and charged the task.
class ProviderStartJob < ApplicationJob
  queue_as :youcam
  # The kit was deleted meanwhile.
  discard_on ActiveJob::DeserializationError

  def perform(render)
    return unless render.claim_start!

    job = Appearance.provider.start(render.operation, render.provider_inputs)
    raise Appearance::Error.new(:provider_error, maybe_charged: true, message: "no task id") if job.external_id.blank?

    render.update!(external_id: job.external_id, started_at: job.started_at)
    render.provider_call&.update!(status: :running)
    ProviderPollJob.set(wait_until: ProviderPollJob.next_poll_at(render.started_at)).perform_later(render)
  rescue Appearance::Error => error
    render.fail_call!(error.reason, refund: !error.maybe_charged?)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { render_id: render.id })
    render.fail_call!(:provider_error, refund: false)
  end
end
