module Ease
  # Ease in words, for people rather than numbers.
  module Words
    EASY = 80
    SOME_CARE = 60
    TRICKY = 40

    # Labels for the ease tags on steps and products.
    TAGS = {
      "pump" => "Pump",
      "flip_cap" => "Flip cap",
      "easy_cap" => "Cap pulls straight off",
      "opens_one_handed" => "Opens with one hand",
      "no_pinch_grip" => "No pinch grip",
      "chunky" => "Chunky, easy to hold",
      "big_handle" => "Big handle",
      "finger_applied" => "Put on with your fingers",
      "forgiving" => "Blends away wobbles",
      "away_from_eyes" => "Away from the eyes",
      "one_step" => "One step, no tools"
    }.freeze

    module_function

    def for(score)
      if score >= EASY then "Easy"
      elsif score >= SOME_CARE then "Some care"
      elsif score >= TRICKY then "Tricky"
      else "Hard"
      end
    end

    def tag(tag)
      TAGS.fetch(tag.to_s)
    end
  end
end
