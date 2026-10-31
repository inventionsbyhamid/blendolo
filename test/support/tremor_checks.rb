require "axe/core"
require "axe/api/run"

# Browser checks shared by system tests: axe (WCAG 2.2 AA rules), and the size of every control.
module TremorChecks
  PHONE = [ 390, 844 ].freeze
  # Buttons, links, label buttons ("Choose a photo") and form controls a person can aim at: visible ones only (a
  # closed details element keeps its content laid out but hidden, and a visually hidden input is aimed at through its
  # label). Links inside a sentence (display: inline) are left out, as WCAG 2.5.8 does;
  # everything else must be at least 64 px tall and wide.
  TARGETS_SCRIPT = <<~JS.freeze
    return Array.from(document.querySelectorAll("a[href], button, summary, label.btn, input:not([type=hidden]), select, textarea, [role=button]"))
      .filter((el) => el.checkVisibility({ visibilityProperty: true }) && el.getClientRects().length > 0)
      .filter((el) => getComputedStyle(el).display !== "inline")
      .filter((el) => !el.classList.contains("sr-only"))
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

  # Pairs of targets closer than gap px (neither inside the other): a shaky second touch lands on the neighbour.
  GAPS_SCRIPT = <<~JS.freeze
    const gap = arguments[0]
    const targets = Array.from(document.querySelectorAll("a[href], button, summary, label.btn, input:not([type=hidden]), select, textarea, [role=button]"))
      .filter((el) => el.checkVisibility({ visibilityProperty: true }) && el.getClientRects().length > 0)
      .filter((el) => getComputedStyle(el).display !== "inline")
      .filter((el) => !el.classList.contains("sr-only"))
    const label = (el) => (el.innerText || el.getAttribute("aria-label") || el.tagName).trim().slice(0, 40)
    const close = []
    targets.forEach((a, i) => targets.slice(i + 1).forEach((b) => {
      if (a.contains(b) || b.contains(a)) return
      const r = a.getBoundingClientRect(), s = b.getBoundingClientRect()
      const dx = Math.max(0, s.left - r.right, r.left - s.right)
      const dy = Math.max(0, s.top - r.bottom, r.top - s.bottom)
      const distance = Math.max(dx, dy)
      if (distance < gap - 0.5) close.push(`${label(a)} / ${label(b)}: ${Math.round(distance)} px`)
    }))
    return close
  JS

  def assert_targets_at_least(size, gap: 24)
    targets = page.evaluate_script("(function() { #{TARGETS_SCRIPT} })()")
    assert_not_empty targets
    small = targets.reject { |target| target["height"] >= size && target["width"] >= size }
    assert_empty small, "Targets under #{size} px on #{page.current_path}: #{small.inspect}"
    close = page.evaluate_script("(function() { #{GAPS_SCRIPT} })(#{gap})")
    assert_empty close, "Targets closer than #{gap} px on #{page.current_path}: #{close.inspect}"
  end

  def on_a_phone
    page.current_window.resize_to(*PHONE)
    yield
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
