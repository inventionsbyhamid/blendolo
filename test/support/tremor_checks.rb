require "axe/core"
require "axe/api/run"

# Browser checks shared by system tests: axe (WCAG 2.2 AA rules), and the size of every control.
module TremorChecks
  PHONE = [ 390, 844 ].freeze
  # Buttons, links and form controls a person can aim at. Links inside a sentence (display: inline) are left out, as
  # WCAG 2.5.8 does; everything else must be at least 64 px tall and wide.
  TARGETS_SCRIPT = <<~JS.freeze
    return Array.from(document.querySelectorAll("a[href], button, summary, input:not([type=hidden]), select, textarea, [role=button]"))
      .filter((el) => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== "hidden")
      .filter((el) => getComputedStyle(el).display !== "inline")
      .map((el) => {
        const box = el.getBoundingClientRect()
        return { label: (el.innerText || el.getAttribute("aria-label") || el.outerHTML).trim().slice(0, 60),
                 width: Math.round(box.width), height: Math.round(box.height) }
      })
  JS

  def assert_axe_clean(impacts: %i[serious critical])
    audit = Axe::Core.new(page).call(Axe::API::Run.new.according_to(:wcag2a, :wcag2aa, :wcag21a, :wcag21aa, :wcag22aa))
    violations = audit.results.violations.select { |rule| impacts.include?(rule.impact) }
    assert_empty violations, -> { violations.flat_map { |rule| [ "#{rule.id} (#{rule.impact}): #{rule.help}", *rule.nodes.map { |node| "  #{node.html}" } ] }.join("\n") }
  end

  def assert_targets_at_least(size)
    targets = page.evaluate_script("(function() { #{TARGETS_SCRIPT} })()")
    assert_not_empty targets
    small = targets.reject { |target| target["height"] >= size && target["width"] >= size }
    assert_empty small, "Targets under #{size} px on #{page.current_path}: #{small.inspect}"
  end

  def on_a_phone
    page.current_window.resize_to(*PHONE)
    yield
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
