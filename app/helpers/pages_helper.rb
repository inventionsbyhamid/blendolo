module PagesHelper
  # The landing page's example: an example person's hands and look, and the two swaps it shows, with the step the ease
  # engine swaps to. The grades on the page come from the engine, so the landing never says what the app won't.
  LANDING_EXAMPLE = {
    person: "rosa",
    swaps: [
      { from: "liquid_matte_lipstick", to: "tinted_balm", was: "Liquid red lipstick", now: "Red tinted balm" },
      { from: "liquid_liner_wing", to: "shadow_liner", was: "Winged liquid liner", now: "Shadow liner" }
    ]
  }.freeze
  # Ease in words, as the landing's coloured labels.
  LEVEL_CLASSES = { "Easy" => "lvl--easy", "Some care" => "lvl--care", "Tricky" => "lvl--hard", "Hard" => "lvl--hard" }.freeze

  # { name:, classic:, easy:, swaps: [{ was:, now:, from:, to:, to_id: }] }, every grade in words from the engine.
  def landing_example
    @landing_example ||= begin
      person = Examples.fetch(LANDING_EXAMPLE[:person])
      profile = Ease::HandProfile.new(**person.hands)
      look = Looks::Catalogue.fetch(person.chosen_look)
      planned = look.plan(profile)[:swaps].index_by { |swap| swap[:from].id }
      words = ->(step) { Ease::Words.for(Ease::Scorer.step(step, profile)) }

      swaps = LANDING_EXAMPLE[:swaps].map do |shown|
        swap = planned.fetch(shown[:from])
        shown.slice(:was, :now).merge(from: words.(swap[:from]), to: words.(swap[:to]), to_id: swap[:to].id)
      end
      { name: person.name, classic: Ease::Words.for(Ease::Scorer.look(look.ease_steps, profile)[:ease]),
        easy: Ease::Words.for(Ease::Scorer.look(look.easy_steps(profile).map(&:step), profile)[:ease]), swaps: }
    end
  end

  def ease_level(words)
    tag.span(words, class: [ "lvl", LEVEL_CLASSES.fetch(words) ])
  end

  # A step's ease with no hand answers, from the ease engine, so guides never drift from it.
  def guide_ease(step_id)
    Ease::Scorer.step(Ease::StepCatalogue.fetch(step_id), Ease::HandProfile.new)
  end

  # The landing photos: webp at 800 px and full size, with a jpeg fallback.
  def landing_picture(name, full:, height:, alt:, sizes:, eager: false, css: "photo")
    sources = "#{image_path("landing/#{name}-800.webp")} 800w, #{image_path("landing/#{name}-full.webp")} #{full}w"
    img_options = { class: css, width: 800, height:, alt: }
    img_options.merge!(eager ? { fetchpriority: "high" } : { loading: "lazy", decoding: "async" })

    tag.picture do
      tag.source(type: "image/webp", srcset: sources, sizes:) + image_tag("landing/#{name}-800.jpg", **img_options)
    end
  end
end
