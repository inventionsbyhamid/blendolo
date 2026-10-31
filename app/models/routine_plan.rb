# The routine a kit follows: the easy steps of the chosen look in the order to do them (detailed steps first while
# hands are fresh, the fix-up step last), each with the look's colour. Stored on kit.routine as
# [{ "step" => id, "colour" => hex or nil, "intensity" => 0..100 or nil }].
module RoutinePlan
  module_function

  def from(look_steps)
    look_steps = look_steps.map { |step| Looks::LookStep.wrap(step) }
    by_id = look_steps.index_by(&:step_id)

    Ease::RoutineOrder.order(look_steps.map(&:step)).map do |step|
      look_step = by_id[step.id]
      { "step" => step.id, "colour" => look_step&.colour, "intensity" => look_step&.intensity }
    end
  end

  # The stored routine as Ease steps, for the step cards and the shopping list.
  def steps(kit)
    kit.routine.map { |entry| Looks::LookStep.wrap(entry).step }
  end
end
