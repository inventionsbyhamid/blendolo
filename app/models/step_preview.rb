# Pictures for a step card: the finished easy preview of the routine's look ("with"), and, when one was made, a
# finished preview of the same look without this step's effect ("without"). The browser compares the two to glow
# where the step goes. Nothing here asks the provider for anything.
module StepPreview
  module_function

  def with(kit)
    return if kit.chosen_look_key.blank?

    kit.renders.done.where(kind: "easy", look_key: kit.chosen_look_key).joins(:result_attachment).order(:id).last
  end

  def without(kit, with_render, step)
    return unless with_render && step.category

    effects = with_render.effects.reject { |effect| effect["category"] == step.category }
    return if effects.size == with_render.effects.size

    attributes = { photo: with_render.photo, look_key: with_render.look_key, kind: "step", reference_photo: nil, effects: }
    Previews.matching(kit.renders.done, attributes).joins(:result_attachment).order(:id).last
  end
end
