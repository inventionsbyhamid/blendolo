# House copy rules for words shown to people: no em or en dashes, and none of these words or phrases.
module CopyRules
  BANNED = [ "cure", "heal", "treat", "treatment for", "diagnose", "guarantee", "perfect", "fix your face",
             "suffering", "sufferer", "victim", "despite", "the shakes", "fight", "battle", "warrior", "journey",
             "flawless" ].freeze
  DASHES = /[\u2013\u2014]/

  def assert_copy_follows_house_rules(text, where)
    assert_no_match DASHES, text, "#{where}: no em or en dashes"
    BANNED.each { |word| assert_no_match(/\b#{Regexp.escape(word)}\b/i, text, "#{where}: #{word}") }
  end
end
