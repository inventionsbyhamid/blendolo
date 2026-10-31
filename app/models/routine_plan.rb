# The routine a kit follows: the easy steps of the chosen look in the order to do them (detailed steps first while
# hands are fresh, the fix-up step last), each with the look's colour. Stored on kit.routine as
# [{ "step" => id, "colour" => hex or nil, "intensity" => 0..100 or nil, "optional" => true when the look can do
# without it }].
module RoutinePlan
  module_function

  def from(look_steps)
    look_steps = look_steps.map { |step| Looks::LookStep.wrap(step) }
    by_id = look_steps.index_by(&:step_id)

    Ease::RoutineOrder.order(look_steps.map(&:step)).map do |step|
      look_step = by_id[step.id]
      { "step" => step.id, "colour" => look_step&.colour, "intensity" => look_step&.intensity }
        .merge(step.optional? ? { "optional" => true } : {})
    end
  end

  # The kit's routine entries. An example person's kit, which is never written to, follows its chosen look.
  def entries(kit)
    return kit.routine if kit.routine.present?
    return [] unless kit.example? && kit.chosen_look_key.present?

    from(LookForKit.find(kit, kit.chosen_look_key).easy_steps)
  end

  # The routine as Ease steps, for the step cards and the shopping list.
  def steps(kit)
    entries(kit).map { |entry| Looks::LookStep.wrap(entry).step }
  end
end
