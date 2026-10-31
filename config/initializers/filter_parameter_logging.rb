# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# Kit and share tokens are the keys to a person's kit; photos, references and sampled colours are about their face.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :image, :reference, :sampled
]

# Redirects to a kit or a share page would print its token: log them as [FILTERED].
Rails.application.config.filter_redirect << %r{/[ks]/}

# The token is part of the path in /k/<token> and /s/<token>, which the "Started GET" line prints in full.
module TokenPathFilter
  TOKEN_PATH = %r{\A/([ks])/[^/?]+}

  def filtered_path
    super.sub(TOKEN_PATH, '/\1/[FILTERED]')
  end
end

ActionDispatch::Request.prepend(TokenPathFilter)
