# The session cookie (encrypted and signed, httponly, SameSite Lax, secure in production) holds the form token and,
# after Google sign in, the user id. It lasts 30 days from the last visit, so a person isn't asked to sign in again on
# every visit; signing out ends it.
Rails.application.config.session_store :cookie_store, key: "_blendolo_session", expire_after: 30.days
