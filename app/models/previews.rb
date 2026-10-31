# Finds or makes the render of some effects (or a transfer) on a photo, so a look viewed twice, or a button tapped
# twice, never asks the provider twice. A new render goes through Render#request! (cache, unit guard, credits, jobs),
# and so does one refused for want of a sign in or credits, once those are there.
# Only POSTs make renders (Previews.for); pages only look them up (Previews.find), so a GET (or a prefetch) never
# spends units. Example kits only ever show their stored previews: they never call the provider.
module Previews
  module_function

  def for(kit, photo, look_key, kind, effects, reference_photo: nil)
    attributes = attributes(photo, look_key, kind, effects, reference_photo)
    return stored(kit, attributes) if kit.example?

    created = false
    render = kit.with_lock do
      matching(kit.renders, attributes).order(:id).last || kit.renders.create!(attributes).tap { created = true }
    end
    render.request! if created || render.awaiting_payment?
    render
  end

  # The existing render, or nil when it hasn't been asked for yet (an example's missing one says it isn't stored).
  def find(kit, photo, look_key, kind, effects, reference_photo: nil)
    attributes = attributes(photo, look_key, kind, effects, reference_photo)
    return stored(kit, attributes) if kit.example?

    matching(kit.renders, attributes).order(:id).last
  end

  # A stand-in shown while a render hasn't been asked for: "Getting your photo ready".
  def waiting(kit, kind)
    Render.new(kit:, kind: kind.to_s, status: :pending)
  end

  def attributes(photo, look_key, kind, effects, reference_photo)
    { photo:, look_key: look_key.to_s, kind: kind.to_s, reference_photo:, effects: effects.as_json }
  end

  # Renders with these attributes. effects is compared as JSON (jsonb equality ignores key order).
  def matching(scope, attributes)
    scope.where(attributes.except(:effects)).where("renders.effects = CAST(? AS jsonb)", attributes[:effects].to_json)
  end

  # An example kit's finished preview of this kind (and look; a transfer has one per kit), or an unsaved failed
  # render that says the example doesn't have it.
  def stored(kit, attributes)
    scope = kit.renders.done.where(kind: attributes[:kind])
    scope = scope.where(look_key: attributes[:look_key]) unless attributes[:kind] == "transfer"
    scope.order(:id).last || Render.new(attributes.merge(kit:, status: :failed, failure_reason: "example"))
  end
end
