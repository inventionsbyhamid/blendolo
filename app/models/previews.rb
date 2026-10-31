# Finds or makes the render of some effects (or a transfer) on a photo, so a look viewed twice, or a button tapped
# twice, never asks the provider twice. A new render goes through Render#request! (cache, unit guard, jobs).
# Example kits only ever show their stored previews: they never call the provider and are never written to.
module Previews
  module_function

  def for(kit, photo, look_key, kind, effects, reference_photo: nil)
    attributes = { photo:, look_key: look_key.to_s, kind: kind.to_s, reference_photo:, effects: effects.as_json }
    return stored(kit, attributes) if kit.example?

    created = false
    render = kit.with_lock do
      matching(kit.renders, attributes).order(:id).last || kit.renders.create!(attributes).tap { created = true }
    end
    render.request! if created
    render
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
    scope.order(:id).last || kit.renders.build(attributes.merge(status: :failed, failure_reason: "example"))
  end
end
