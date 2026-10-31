require "digest"

# Blendolo's voice: every line the app reads aloud, recorded once in one synthetic voice (script/voice/generate.rb)
# and served from public/voice/<key>.mp3. A line's key is the SHA-256 of its text with the spaces tidied (normalize).
# The browser hashes the words on the page the same way (voice/player.js), so a recording plays only when the words
# match it exactly. A line without one is read by the phone's own voice.
#
# The lines: every step card as "Read it to me" reads it (also with the optional line, for the steps a look can do
# without), and everything the hands-free photo page says aloud.
module Voice
  DIR = Rails.root.join("public/voice")
  MANIFEST = DIR.join("manifest.json")

  # What the hands-free photo page says aloud: capture/gate.js MESSAGES (the eyes note is shown on the review screen,
  # and only said as part of "Got it. ...") and capture_controller.js, with photos/new's prompt for "Choose a photo"
  # in both wordings.
  CAPTURE = [
    "Look straight at the phone",
    "Come a little closer",
    "Step back a little",
    "Open your eyes wide",
    "Hold still",
    "Got it",
    "Got it. Your eyes looked a little closed, so the preview may show softer liner.",
    "Try a photo of just you",
    "Tap Take the photo when you're ready",
    "Checking the photo",
    "We couldn't find a face in that photo. Please choose another.",
    "Choose an old photo of you wearing the look.",
    "Choose an old photo of them wearing the look."
  ].freeze

  # The photo timers count down aloud from their seconds (3 and 10).
  COUNTDOWN = (1..10).map(&:to_s).freeze

  # One line: its text as shown, and where it comes from (for people reading the list).
  Line = Data.define(:text, :source) do
    def key = Voice.key(text)
  end

  class << self
    def normalize(text) = text.to_s.gsub(/[[:space:]]+/, " ").strip

    def key(text) = Digest::SHA256.hexdigest(normalize(text))

    # A card's paragraphs as one text, the way "Read it to me" joins them: each ends with a full stop (or its own
    # ! or ?), one space between.
    def join(parts)
      parts.map { |part| normalize(part) }.reject(&:empty?).map { |part| part.match?(/[.!?]\z/) ? part : "#{part}." }.join(" ")
    end

    # What "Read it to me" reads on a step's card (routines/step.html.erb and routines/_card_text).
    def card(step)
      join([ step.optional_why, step.instruction, ("Why this is easier: #{step.why_easier}" if step.why_easier.present?),
             ("Tip: #{step.tips.first}" if step.tips.any?) ].compact)
    end

    # Every line, in a fixed order: the step cards in catalogue order, the optional cards, then the photo page's.
    def lines
      cards = Ease::StepCatalogue.all.map { |step| Line.new(card(step), "step #{step.id}") }
      optional = optional_steps.map { |step| Line.new(card(step), "step #{step.id}, optional") }
      capture = capture_lines.map { |text| Line.new(text, "capture") }
      (cards + optional + capture).uniq(&:key)
    end

    # Everything the hands-free photo page can say.
    def capture_lines = CAPTURE + COUNTDOWN

    # The steps a look marks optional, and the easier steps they can become (which stay optional), as optional steps.
    def optional_steps
      ids = Looks::Catalogue.all.flat_map(&:steps).select(&:optional).map(&:step_id)
      ids = ids.flat_map { |id| [ id, *Ease::StepCatalogue.fetch(id).swap_ids ] }.uniq
      ids.map { |id| Ease::StepCatalogue.fetch(id).as_optional }
    end

    # { key => { "text", "audio" (a digest of the file, so a new take gets a new URL), "seconds" } } for every
    # recorded line, from public/voice/manifest.json.
    def manifest
      @manifest ||= MANIFEST.exist? ? JSON.parse(MANIFEST.read).fetch("lines").freeze : {}.freeze
    end

    # { key => audio digest } for those of these texts that have a recording, for a page to hand to voice/player.js.
    def versions(texts)
      texts.map { |text| key(text) }.uniq.filter_map { |key| [ key, manifest[key]["audio"] ] if manifest.key?(key) }.to_h
    end

    def path(text) = DIR.join("#{key(text)}.mp3")
  end
end
