# Gets a render's image from the appearance provider, spending as few units as possible.
#
# request! keys the render by its inputs (input_hash: operation, photo bytes, and the effects or the reference photo's
# bytes) and then, in order:
#   :example  an example kit's render: nothing changes, nothing is called
#   :waiting  the render is already running, or a call with the same inputs is in flight: it finishes with that call
#   :cached   a finished call with the same inputs left a result in our storage: copy it, no call
#   a refusal from UnitGuard (:example, :kit_cap, :daily_cap, :floor): the render fails with that reason
#   :queued   a new call: ProviderStartJob, then ProviderPollJob until done, failed or out of time
# Two requests for the same inputs never start two paid tasks: the call row and the render are claimed atomically.
# Each change of state is broadcast to the kit's stream as a replace of renders/_render (dom_id(render)).
module ProviderTracked
  extend ActiveSupport::Concern

  def operation = transfer? ? :transfer : :makeup

  def request!
    return :example if kit.example? # example kits only show their stored previews, and refuse changes
    return :waiting if running?

    update!(input_hash: compute_input_hash, status: :pending, failure_reason: nil)
    call = provider_call

    if call&.done? && (source = earlier_result)
      begin
        copy_result_from!(source)
        return :cached
      rescue ActiveStorage::FileNotFoundError
        # The stored copy is gone: call again, within the caps.
      end
    end
    return :waiting if call&.in_flight?

    verdict = UnitGuard.check(kit:, operation:)
    return verdict.tap { fail!(verdict) } unless verdict == :ok

    cost = Appearance.provider.feature_cost(operation)
    if call
      return :waiting unless call.claim!(kit:, units: units_after(call, cost))
    else
      ProviderCall.create!(kit:, operation: operation.to_s, input_hash:, status: :pending, units: cost)
    end
    ProviderStartJob.perform_later(self)
    :queued
  rescue ActiveRecord::RecordNotUnique
    :waiting
  end

  # Moves a pending render to running for exactly one caller: the one that starts the provider task.
  def claim_start!
    claimed = Render.where(id:, status: Render.statuses[:pending])
      .update_all(status: Render.statuses[:running], started_at: Time.current, updated_at: Time.current) == 1
    return false unless claimed

    reload
    broadcast_render
    true
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

  # Downloads a done outcome (outside any transaction), then stores it once even if two polls race, and finishes
  # the renders that waited. A failed download raises, so the poll job can ask again for a fresh link.
  def finish_from!(outcome, provider)
    image = provider.download(outcome)
    finished = with_lock do
      next false unless running?

      result.attach(io: image.io, filename: image.filename, content_type: image.content_type)
      update!(status: :done, failure_reason: nil)
      provider_call&.update!(status: :done, response: { "content_type" => image.content_type, **outcome.data.to_h.stringify_keys })
      true
    end
    return unless finished

    broadcast_render
    waiting_renders.each { |render| render.copy_result_from!(self) }
  end

  # Fails this render, its call and the renders that waited for it. refund: the provider gave the units back or
  # never took them (engine errors, definite refusals); anything else may have been charged and keeps its units.
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

    # Units the call counts today: what it already holds (0 when refunded) if it was made today, plus this call.
    def units_after(call, cost)
      (call.day == Date.current ? call.units : 0) + cost
    end

    def broadcast_render
      broadcast_replace_later_to kit
    end
end
