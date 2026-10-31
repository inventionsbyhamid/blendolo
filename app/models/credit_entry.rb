# One change to a user's credits: delta (+ added, - spent), why, what for (source), and the balance after it.
# Rows are only ever added (Credits writes them, under a lock on the user's row); a check constraint keeps
# balance_after at zero or more.
class CreditEntry < ApplicationRecord
  belongs_to :user

  enum :reason, { signup_grant: 0, pack_purchase: 1, clinic_grant: 2, render: 3, transfer: 4, refund: 5, admin: 6 },
    validate: true, scopes: false, instance_methods: false

  # Render and transfer debits repeat when a render is asked for again; every other reason happens once per source
  # (a unique index holds it).
  REPEATABLE = %w[render transfer].freeze

  validates :delta, numericality: { only_integer: true, other_than: 0 }
  validates :balance_after, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.once_per_source?(reason)
    REPEATABLE.exclude?(reason.to_s)
  end

  def readonly?
    persisted?
  end
end
