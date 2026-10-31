# Accounts for tests: users with credits, and Google sign in through OmniAuth's test mode (no network).
module AccountHelpers
  def make_user(credits: 10, name: "Rosa Diaz", email: nil)
    user = User.create!(provider: "google_oauth2", uid: "g-#{SecureRandom.hex(8)}", name:,
      email: email || "person-#{SecureRandom.hex(4)}@example.com")
    Credits.grant!(user, credits, reason: :admin, source: nil) if credits.positive?
    user
  end

  # What Google says about the person who signs in next.
  def mock_google(user = nil, uid: user&.uid || "g-#{SecureRandom.hex(8)}", name: user&.name || "Rosa Diaz",
                  email: user&.email || "rosa@example.com")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid:, info: { name:, email:, image: "https://lh3.googleusercontent.com/a/rosa" }
    )
  end

  # Request tests: the browser's POST with the button's origin, then Google's redirect back to the callback.
  def sign_in_as(user, origin: nil)
    mock_google(user)
    post "/auth/google_oauth2", params: { origin: }.compact
    follow_redirect!
  end

  # System tests: the "Sign in with Google" button on the sign in page.
  def sign_in_in_browser(user)
    mock_google(user)
    visit sign_in_path
    click_on "Sign in with Google"
    assert_selector "h1", text: "Your account"
  end
end
