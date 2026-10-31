# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# Kit and share tokens are the keys to a person's kit; photos, references and sampled colours are about their face.
# Active Storage's signed and encoded ids are short-lived keys to those photos.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :image, :reference, :sampled, :signed_id, :signed_blob_id, :encoded_key, :encoded_token
]

# Redirects to a kit, a share page or a stored file would print their key: log them as [FILTERED].
Rails.application.config.filter_redirect.push(%r{/[ks]/}, %r{/rails/active_storage/})

# The "Started GET" line prints the path in full, and some paths carry a key:
#   /k/<token>/...  /s/<token>/...                     kits and shares
#   /rails/active_storage/<blobs|representations>/<redirect|proxy>/<signed id>/...   stored photos and previews
#   /rails/active_storage/disk/<encoded key>/...       files on local disk
module TokenPathFilter
  TOKEN_PATH = %r{\A/([ks])/[^/?]+}
  STORAGE_PATH = %r{\A(/rails/active_storage/(?:(?:blobs|representations)/(?:redirect|proxy)|disk))/[^?]+}

  def filtered_path
    super.sub(TOKEN_PATH, '/\1/[FILTERED]').sub(STORAGE_PATH, '\1/[FILTERED]')
  end
end

ActionDispatch::Request.prepend(TokenPathFilter)
