require "test_helper"
require "support/account_helpers"

# Taking credits back when the money went back, and repeat checks that stay inside one account.
class CreditsClawbackTest < ActiveSupport::TestCase
  include AccountHelpers

  test "a claw back takes what is left, never below zero, once per source" do
    user = make_user(credits: 10)

    entry = Credits.claw_back!(user, 16, source: "dodo:pay_1:ref_1")

    assert_equal [ -10, 0 ], [ entry.delta, Credits.balance(user) ]
    Credits.grant!(user, 5, reason: :admin, source: nil)
    assert_equal entry, Credits.claw_back!(user, 16, source: "dodo:pay_1:ref_1")
    assert_equal 5, Credits.balance(user)
  end

  test "nothing left to take is nil" do
    user = make_user(credits: 0)

    assert_nil Credits.claw_back!(user, 16, source: "dodo:pay_2:ref_2")
    assert_empty user.credit_entries.where(reason: "clawback")
  end

  test "a source another account used is never handed back as this account's entry" do
    first, second = make_user(credits: 0), make_user(credits: 0)
    Credits.grant!(first, 16, reason: :pack_purchase, source: "dodo:pay_same")

    assert_raises(ActiveRecord::RecordNotFound) { Credits.grant!(second, 16, reason: :pack_purchase, source: "dodo:pay_same") }
    assert_equal [ 16, 0 ], [ Credits.balance(first), Credits.balance(second) ]
  end
end
