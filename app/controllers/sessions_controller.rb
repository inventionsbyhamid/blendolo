# Google sign in and sign out, with plain Rails sessions. OmniAuth (config/initializers/omniauth.rb) does the OAuth
# exchange:
#   GET    /sign_in                       new: the "Sign in with Google" button, for links from anywhere
#   POST   /auth/google_oauth2            OmniAuth checks the form's authenticity token, then sends the person to Google
#   GET    /auth/google_oauth2/callback   create: the account, a fresh session, the free credits, this device's kit
#   GET    /auth/failure                  failure: back to the button
#   DELETE /sign_out                      destroy
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[create failure], with: -> { too_many_requests }
  rate_limit to: 10, within: 1.minute, only: :destroy, with: -> { too_many_requests }

  def new
    return redirect_to(account_path) if signed_in?

    @origin = url_from(params[:origin])
  end

  def create
    user = User.from_omniauth(request.env.fetch("omniauth.auth"))
    origin = url_from(request.env["omniauth.origin"])
    kit = remembered_kit
    sign_in(user)
    Credits.grant_signup!(user)
    user.claim!(kit) if kit&.purge_after&.future?
    redirect_to origin || account_path, notice: "You're signed in, #{user.first_name}."
  rescue ActiveRecord::RecordInvalid
    redirect_to sign_in_path, notice: "We couldn't sign you in with that Google account. Please try again."
  end

  def failure
    redirect_to sign_in_path, notice: "Signing in didn't finish. Please try again."
  end

  def destroy
    sign_out
    redirect_to root_path, notice: "You're signed out."
  end
end
