module ApplicationHelper
  # Where people reach us (privacy and accessibility pages).
  CONTACT_URL = "https://github.com/inventionsbyhamid/blendolo/issues".freeze

  # "My hands today" for the current kit: 0 steady, 1 a bit shaky (the default), 2 very shaky or stiff. The layout
  # puts it on <body data-hands>, which sets target sizes and the repeat-tap window.
  def hands_today
    @kit&.hands_today || 1
  end
end
