require "test_helper"
require "support/account_helpers"

class CreditsTest < ActiveSupport::TestCase
  include AccountHelpers

  test "grants and debits keep a ledger with the balance after each change" do
    user = make_user(credits: 0)

    Credits.grant!(user, 16, reason: :pack_purchase, source: "pay_1")
    Credits.debit!(user, 2, reason: :transfer, source: "render:1")
    Credits.debit!(user, 1, reason: :render, source: "render:2")

    assert_equal 13, Credits.balance(user)
    assert_equal [ [ 16, "pack_purchase", 16 ], [ -2, "transfer", 14 ], [ -1, "render", 13 ] ],
      user.credit_entries.order(:id).map { [ it.delta, it.reason, it.balance_after ] }
  end

  test "a grant with the same reason and source again changes nothing" do
    user = make_user(credits: 0)

    first = Credits.grant!(user, 16, reason: :pack_purchase, source: "pay_1")
    again = Credits.grant!(user, 16, reason: :pack_purchase, source: "pay_1")
    Credits.grant!(user, 40, reason: :clinic_grant, source: "pay_1")

    assert_equal first, again
    assert_equal 56, Credits.balance(user)
  end

  test "a debit beyond the balance raises and writes nothing" do
    user = make_user(credits: 1)

    assert_raises(Credits::Insufficient) { Credits.debit!(user, 2, reason: :transfer, source: "render:9") }
    assert_equal 1, Credits.balance(user)
    assert_equal 1, user.credit_entries.count
  end

  test "amounts are whole and positive" do
    user = make_user(credits: 5)

    assert_raises(ArgumentError) { Credits.grant!(user, 0, reason: :admin, source: nil) }
    assert_raises(ArgumentError) { Credits.debit!(user, -1, reason: :render, source: "render:1") }
    assert_raises(ArgumentError) { Credits.grant!(user, 1.5, reason: :admin, source: nil) }
  end

  test "the database refuses a negative balance and a row change" do
    user = make_user(credits: 1)

    assert_raises(ActiveRecord::ReadOnlyRecord) { user.credit_entries.first.update!(delta: 100) }
    assert_raises(ActiveRecord::StatementInvalid) do
      CreditEntry.insert!({ user_id: user.id, delta: -2, reason: CreditEntry.reasons[:render], balance_after: -1 })
    end
  end

  test "the free credits come once per Google account, even after the account is deleted" do
    user = make_user(credits: 0)

    Credits.grant_signup!(user)
    Credits.grant_signup!(user)
    assert_equal 2, Credits.balance(user)

    provider, uid = user.provider, user.uid
    user.destroy_everything!
    again = User.create!(provider:, uid:, email: "rosa@example.com")
    assert_nil Credits.grant_signup!(again)
    assert_equal 0, Credits.balance(again)
    assert_equal 1, SignupGrant.count
    assert_no_match(/#{uid}/, SignupGrant.sole.account_digest)
  end

  test "a refund is once per source" do
    user = make_user(credits: 3)

    Credits.refund!(user, 2, source: "credit_entry:5")
    Credits.refund!(user, 2, source: "credit_entry:5")

    assert_equal 5, Credits.balance(user)
  end
end
