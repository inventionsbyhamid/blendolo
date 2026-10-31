# Starts the provider task for a render that ProviderTracked#request! queued, scheduling the first poll first.
# Only the job that claims the render (pending to running) calls the provider. Any failure fails the render: a
# definite refusal, or our own error before anything is sent (reading the photos), is refunded; anything else (a
# server or network error, an error during the call) keeps its units, because the provider may have started and
# charged the task.
class ProviderStartJob < ApplicationJob
  queue_as :youcam
  # The kit was deleted meanwhile.
  discard_on ActiveJob::DeserializationError

  def perform(render)
    return unless render.claim_start!

    # The poll chain starts before the provider is called, so a worker that dies mid-start still leaves a poll that
    # times the render out (a render with no task id just waits for its deadline).
    ProviderPollJob.set(wait_until: ProviderPollJob.next_poll_at(render.started_at)).perform_later(render)

    # Reading the photos is ours: if it fails, nothing was sent to the provider, so the credits go back.
    inputs = begin
      render.provider_inputs
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { render_id: render.id })
      return render.fail_call!(:provider_error, refund: true)
    end

    job = Appearance.provider.start(render.operation, inputs)
    raise Appearance::Error.new(:provider_error, maybe_charged: true, message: "no task id") if job.external_id.blank?

    render.update!(external_id: job.external_id)
    render.provider_call&.update!(status: :running)
  rescue Appearance::Error => error
    render.fail_call!(error.reason, refund: !error.maybe_charged?)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { render_id: render.id })
    render.fail_call!(:provider_error, refund: false)
  end
end
