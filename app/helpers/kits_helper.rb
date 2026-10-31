module KitsHelper
  HANDS_TODAY = [ "Steady", "A bit shaky", "Very shaky or stiff" ].freeze

  # The five "Your hands" questions with their three answers, in the person's words or, for a helper, about
  # the person they help.
  QUESTIONS = {
    tremor: { self: "Do your hands shake?", helper: "Do their hands shake?", answers: [ "No", "A little", "A lot" ] },
    pinch: { self: "Is pinching or gripping small things hard or sore?",
             helper: "Is pinching or gripping small things hard or sore for them?", answers: %w[No Sometimes Yes] },
    one_hand: { self: "Do you mostly use one hand?", helper: "Do they mostly use one hand?",
                answers: [ "Both", "Mostly left", "Mostly right" ] },
    fatigue: { self: "Do your arms tire quickly?", helper: "Do their arms tire quickly?", answers: %w[No Sometimes Yes] },
    near_vision: { self: "Is close-up reading hard?", helper: "Is close-up reading hard for them?",
                   answers: [ "No", "A little", "Yes" ] }
  }.freeze

  # Setting up a kit: consent, five questions, a photo.
  SETUP_STEPS = 7

  def hand_question(kit, question)
    QUESTIONS.fetch(question).fetch(kit.helper? ? :helper : :self)
  end

  def hand_answers(question)
    QUESTIONS.fetch(question).fetch(:answers)
  end

  # "you" or "they", for copy that speaks to the person or to their helper.
  def you_or_they(kit, you, they)
    kit.helper? ? they : you
  end

  def kit_link(kit)
    kit_url(kit, host: request.host_with_port, protocol: request.protocol)
  end

  # Where to carry on: the first thing not done yet.
  def next_step_for(kit)
    if kit.consented_at.nil? then [ "Carry on: before we start", kit_consent_path(kit) ]
    elsif (number = Kit::HAND_QUESTIONS.index { |question| kit.public_send(question).nil? })
      [ "Carry on: your hands", kit_hand_path(kit, number + 1) ]
    elsif !kit.photos.today.exists? then [ "Carry on: your photo", new_kit_photo_path(kit) ]
    elsif RoutinePlan.entries(kit).empty? then [ "Pick a look", kit_looks_path(kit) ]
    else [ "Open your step cards", kit_routine_path(kit) ]
    end
  end
end
