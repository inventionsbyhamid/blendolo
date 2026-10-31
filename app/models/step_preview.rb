# The picture for a step card: the finished easy preview of the routine's look, zoomed to the step's part of the face
# on the card. Nothing here asks the provider for anything.
module StepPreview
  module_function

  def with(kit)
    return if kit.chosen_look_key.blank?

    kit.renders.done.where(kind: "easy", look_key: kit.chosen_look_key).joins(:result_attachment).order(:id).last
  end
end
