module ApplicationHelper
  # Where people reach us (privacy and accessibility pages).
  CONTACT_URL = "https://github.com/inventionsbyhamid/blendolo/issues".freeze
  # The source code, linked from every page's footer.
  SOURCE_URL = "https://github.com/inventionsbyhamid/blendolo".freeze

  # "My hands today" for the current kit: 0 steady, 1 a bit shaky (the default), 2 very shaky or stiff. The layout
  # puts it on <body data-hands>, which sets target sizes and the repeat-tap window.
  def hands_today
    return 1 unless @kit
    return session[:example_hands_today] || @kit.hands_today if @kit.example?

    @kit.hands_today
  end
end
