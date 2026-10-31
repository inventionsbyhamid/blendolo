require "nokogiri"

# The copy rules from the plan, as a check on rendered HTML: no em or en dashes, none of the banned words. It reads
# what people see or hear: text, alt and label attributes, meta tags, and the JSON-LD search engines show.
module CopyRules
  DASHES = /[–—]/
  BANNED = [
    "cure", "heal", "treat", "treatment for", "diagnose", "guarantee", "perfect", "fix your face", "suffering",
    "sufferer", "victim", "despite", "the shakes", "fight", "battle", "warrior", "journey"
  ].freeze
  BANNED_PATTERN = /\b(?:#{BANNED.map { |word| Regexp.escape(word).gsub("\\ ", "\\s+") }.join("|")})\b/i
  # Proper names that contain a banned word.
  ALLOWED_NAMES = [ "Perfect Corp" ].freeze
  READ_ATTRIBUTES = %w[alt title aria-label placeholder content value].freeze

  def self.problems(html)
    copy = readable_copy(html)
    ALLOWED_NAMES.each { |name| copy = copy.gsub(name, "") }
    found = copy.scan(DASHES).map { |dash| "dash #{dash.inspect}" }
    found + copy.scan(BANNED_PATTERN).map { |word| "banned word #{word.inspect}" }
  end

  def self.readable_copy(html)
    document = Nokogiri::HTML(html)
    document.css("script:not([type='application/ld+json']), style, template").each(&:remove)
    attributes = document.xpath("//@*").select { |attribute| READ_ATTRIBUTES.include?(attribute.name) }
    meta_names = document.css("meta[name], meta[property]").map { |meta| meta["content"] }
    [ document.text, *attributes.map(&:value), *meta_names ].join("\n")
  end
end
