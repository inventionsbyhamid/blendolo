# The Clinic plan's client list (GET /clinic): one kit per client, with the client's name or initials, and each
# client's kit, share links and printed routine one tap away. "New client kit" (POST /clinic/kits) starts a kit in
# the account for someone the clinic helps. Only while the account's Clinic plan is on (User#clinic?).
class ClinicsController < ApplicationController
  include RequiresSignIn

  before_action :require_clinic
  rate_limit to: 10, within: 1.minute, only: :create_kit, with: -> { too_many_requests }

  # A second "New client kit" with the same name this soon is the same tap again: it opens the first kit.
  REPEAT_WINDOW = 30.seconds

  def show
    private_page
    @kits = current_user.live_kits
  end

  def create_kit
    label = params[:label].to_s.squish
    return redirect_to(clinic_path, notice: "Type the client's name or initials first.") if label.empty?

    kit = repeat_of(label) || current_user.kits.create!(path: :helper, label:)
    remember_kit(kit)
    redirect_to kit_consent_path(kit)
  rescue ActiveRecord::RecordInvalid
    redirect_to clinic_path, notice: "Use #{Kit::LABEL_MAX} letters or fewer for the client's name."
  end

  private
    def require_clinic
      return if current_user.clinic?

      redirect_to pricing_path(anchor: "clinic"), notice: "The client list comes with the Clinic plan."
    end

    def repeat_of(label)
      current_user.kits.where(label:, created_at: REPEAT_WINDOW.ago..).order(:id).last
    end

    def sign_in_origin
      clinic_path
    end
end
