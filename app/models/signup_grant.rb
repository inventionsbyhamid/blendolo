# Remembers that an account at a sign in provider had its free credits, so they come once per Google account, even if
# the account here is deleted and made again. Keeps only a one-way HMAC of the provider and its user id.
class SignupGrant < ApplicationRecord
  def self.digest_for(user)
    key = Rails.application.key_generator.generate_key("blendolo signup grants", 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, "#{user.provider}:#{user.uid}")
  end
end
