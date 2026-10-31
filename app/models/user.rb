# Someone who signed in (with Google; no passwords). Credits (Credits, CreditEntry) and kits belong to the account.
# clinic_until: a clinic plan is active until then (billing sets it); clinic? reads it.
class User < ApplicationRecord
  # destroy_everything! deletes the kits' rows with the account's, then their files.
  has_many :kits, dependent: nil
  has_many :credit_entries, dependent: :delete_all

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :provider, :uid, :email, presence: true

  # The account for a sign in, made or brought up to date from what the provider says.
  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider.to_s, uid: auth.uid.to_s)
    user.email = auth.info.email.presence || user.email
    user.name = auth.info.name.presence || user.name
    user.avatar_url = auth.info.image.presence || user.avatar_url
    user.save!
    user
  rescue ActiveRecord::RecordNotUnique
    # The same person signing in twice at once: the other request made the account.
    find_by!(provider: auth.provider.to_s, uid: auth.uid.to_s)
  end

  def first_name
    name.to_s.split.first.presence || email.to_s.split("@").first
  end

  def clinic?
    clinic_until.present? && clinic_until.future?
  end

  def credits
    Credits.balance(self)
  end

  # Kits still open (not past their retention), most recently used first.
  def live_kits
    kits.where(purge_after: Time.current..).order(last_active_at: :desc)
  end

  # Puts a kit that is in no account into this one (never an example kit). True when the kit is in this account
  # afterwards. Atomic: two accounts claiming the same kit at once can't both get it.
  def claim!(kit)
    return false if kit.example?
    return kit.user_id == id if kit.user_id

    Kit.where(id: kit.id, user_id: nil).where.not(path: Kit.paths[:example]).update_all(user_id: id, updated_at: Time.current)
    kit.reload.user_id == id
  end

  # "Delete my account": every kit with its photos and previews (Kit#destroy_everything!), the credits, then the
  # account. The signup grant's one-way code stays, so the free credits stay once per Google account.
  # All rows go in one transaction with the account's row locked (a kit or a credit made meanwhile waits, then finds
  # no account); the stored files go after the commit.
  def destroy_everything!
    files = transaction do
      lock!
      found = kits.reload.flat_map(&:destroy_rows!)
      destroy!
      found
    end
    Kit.purge_files(files)
  end
end
