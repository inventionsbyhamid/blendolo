# Gets a render's image from the appearance provider, spending as few units as possible.
#
# request! keys the render by its inputs (input_hash: operation, photo bytes, and the effects or the reference photo's
# bytes) and then, in order:
#   :cached   a finished call with the same inputs left a result in our storage: copy it, no call
#   :waiting  a call with the same inputs is in flight: this render finishes with it
#   a refusal from UnitGuard (:example, :kit_cap, :daily_cap, :floor): the render fails with that reason
#   :queued   a new call: ProviderStartJob, then ProviderPollJob until done, failed or out of time
# Each change of state is broadcast to the kit's stream as a replace of renders/_render (dom_id(render)).
module ProviderTracked
  extend ActiveSupport::Concern

  # An in-flight call older than this is taken as lost, and the next request calls again.
  STALE_AFTER = 5.minutes

  def operation = transfer? ? :transfer : :makeup

  def request!
    update!(input_hash: compute_input_hash, status: :pending, failure_reason: nil)
    call = provider_call

    if call&.done? && (source = earlier_result)
      copy_result_from!(source)
      return :cached
    end
    return :waiting if call && (call.pending? || call.running?) && call.updated_at > STALE_AFTER.ago

    verdict = UnitGuard.check(kit:, operation:)
    return verdict.tap { fail!(verdict) } unless verdict == :ok

    call ||= ProviderCall.new(operation: operation.to_s, input_hash:)
    call.update!(kit:, status: :pending, units: units_after(call), day: Date.current, response: {})
    ProviderStartJob.perform_later(self)
    :queued
  rescue ActiveRecord::RecordNotUnique
    :waiting
  end

  def provider_call
    ProviderCall.find_by(operation: operation.to_s, input_hash:) if input_hash
  end

  def provider_inputs
    if transfer?
      { photo: photo.to_appearance_image, reference: reference_photo.to_appearance_image }
    else
      { photo: photo.to_appearance_image, effects: }
    end
  end

  def provider_job
    Appearance::Job.new(operation:, external_id:, started_at:)
  end

  # Downloads a done outcome into result, once even if two polls race, then finishes the renders that waited.
  def finish_from!(outcome, provider)
    finished = with_lock do
      next false unless running?

      image = provider.download(outcome)
      result.attach(io: image.io, filename: image.filename, content_type: image.content_type)
      update!(status: :done, failure_reason: nil)
      provider_call&.update!(status: :done, response: { "content_type" => image.content_type, **outcome.data.to_h.stringify_keys })
      true
    end
    return unless finished

    broadcast_render
    waiting_renders.each { |render| render.copy_result_from!(self) }
  rescue Appearance::Error => error
    fail_call!(error.reason, refund: false)
  end

  # Fails this render, its call and the renders that waited for it. refund: the provider gave the units back
  # (engine errors, refused starts); a call we stopped waiting for may still have been charged.
  def fail_call!(reason, refund:)
    fail!(reason)
    provider_call&.update!(status: :failed, **(refund ? { units: 0 } : {}))
    waiting_renders.each { |render| render.fail!(reason) }
  end

  def fail!(reason)
    update!(status: :failed, failure_reason: reason.to_s)
    broadcast_render
  end

  def copy_result_from!(source)
    result.attach(io: StringIO.new(source.result.download), filename: source.result.filename.to_s,
      content_type: source.result.content_type)
    update!(status: :done, failure_reason: nil)
    broadcast_render
  end

  private
    def compute_input_hash
      subject = transfer? ? reference_photo.content_sha256! : canonical_json(effects)
      Digest::SHA256.hexdigest([ operation, photo.content_sha256!, subject ].join("\n"))
    end

    def canonical_json(value)
      sorted = ->(item) do
        case item
        when Hash then item.stringify_keys.sort.to_h.transform_values(&sorted)
        when Array then item.map(&sorted)
        else item
        end
      end
      JSON.generate(sorted.call(value))
    end

    def earlier_result
      Render.done.where(input_hash:).where.not(id:).joins(:result_attachment).order(updated_at: :desc).first
    end

    def waiting_renders
      Render.pending.where(input_hash:).where.not(id:)
    end

    # Units the call counts today. A call made again on the day it was first made adds to it; a failed one was refunded.
    def units_after(call)
      spent = call.persisted? && call.day == Date.current && !call.failed? ? call.units : 0
      spent + Appearance.provider.feature_cost(operation)
    end

    def broadcast_render
      broadcast_replace_later_to kit
    end
end
