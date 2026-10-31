# Words about signing in and credits, shown where a preview on a person's own face is paid for.
module CreditsHelper
  SIGN_IN = "Sign in to see this on your face. Free for your first look.".freeze
  # The signature look costs more than the free credits: say so before anyone signs in for it.
  def signature_sign_in_words
    "Sign in to see your signature look on your face. It uses #{pluralize(signature_cost, "credit")}. " \
      "Your #{Credits.signup_amount} free credits cover one look on your face."
  end

  def signature_cost
    Credits.cost(:transfer) + Credits.cost(:makeup)
  end
  OUT_OF_CREDITS = "You are out of credits. Get more to see this on your face.".freeze
  OTHER_ACCOUNT = "This kit is in another account. Sign in with that account to see it on your face.".freeze

  # "Uses 2 credits. You have 14."
  def credits_cost_words(cost, balance)
    "Uses #{pluralize(cost, "credit")}. You have #{balance}."
  end

  # "You have 14 credits. A look on your face uses 2."
  def credits_balance_words(balance)
    "You have #{pluralize(balance, "credit")}. A look on your face uses #{Credits.look_cost}."
  end

  # Not enough for this: out of credits, or a few short.
  def credits_short_words(cost, balance)
    return OUT_OF_CREDITS if balance.zero?

    "#{credits_cost_words(cost, balance)} Get more to see this on your face."
  end

  # A kit's name in a list: its label, or what it's for.
  def kit_name(kit)
    kit.label.presence || (kit.helper? ? "Kit for someone you help" : "Your kit")
  end
end
