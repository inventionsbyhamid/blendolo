module LooksHelper
  # The picture of a look on a model, or nil while it isn't in the assets yet.
  def look_thumbnail(look)
    path = look.thumbnail.to_s
    path if path.present? && Rails.application.assets.load_path.find(path)
  end

  # The look's own colours (main shade of each coloured step), up to four, for a swatch when there's no picture.
  def look_colours(look)
    look.steps.filter_map { |step| Array(step.colour).first }.uniq.first(4)
  end

  # Colour dots as SVG (fill attributes, not inline styles, so the content security policy allows them).
  def colour_swatch(colours)
    circles = colours.each_with_index.map do |colour, index|
      tag.circle(cx: 30 + index * 46, cy: 34, r: 26, fill: colour, stroke: "#FFFFFF", "stroke-width": 4)
    end
    tag.svg(safe_join(circles), class: "swatch", viewBox: "0 0 #{40 + [ colours.size, 1 ].max * 46} 68",
      "aria-hidden": "true", focusable: "false")
  end

  # "Hard -> Some care": the classic look's ease, then the easy version's, for these hands. Screen readers hear
  # "Classic: Hard, easy version: Some care".
  def ease_change(look)
    safe_join([
      tag.span("Classic: ", class: "sr-only"), look.classic_words, tag.span(" \u2192 ", "aria-hidden": "true"),
      tag.span(", easy version: ", class: "sr-only"), look.easy_words
    ])
  end

  # "Hardest step you need: winged liquid liner" (optional steps never count, so the hardest one is a step you need)
  def hardest_step_words(ease)
    step = ease[:hardest_step]
    "Hardest step you need: #{step.name.downcase_first}" if step
  end
end
