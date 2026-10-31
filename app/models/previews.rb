# Finds or makes the render of some effects (or a transfer) on a photo, so a look viewed twice, or a button tapped
# twice, never asks the provider twice. A new render goes through Render#request! (cache, unit guard, jobs).
# Example kits only ever show stored previews: they never call the provider.
module Previews
  module_function

  def for(kit, photo, look_key, kind, effects, reference_photo: nil)
    attributes = { photo:, look_key: look_key.to_s, kind: kind.to_s, reference_photo:, effects: effects.as_json }
    return example_preview(kit, attributes) if kit.example?

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

  def example_preview(kit, attributes)
    matching(kit.renders, attributes).order(:id).last ||
      ExampleKit.stored_render(kit, attributes) ||
      kit.renders.create!(attributes.merge(status: :failed, failure_reason: "example"))
  end
end
