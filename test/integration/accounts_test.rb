require "test_helper"
require "support/account_helpers"
require "support/kit_helpers"

class AccountsTest < ActionDispatch::IntegrationTest
  include AccountHelpers
  include KitHelpers

  test "the account page needs a sign in" do
    get account_path
    assert_redirected_to sign_in_path(origin: account_path)
  end

  test "the account page shows who, the credits in words and the kits" do
    user = make_user(credits: 14, name: "Rosa Diaz", email: "rosa@example.com")
    make_kit.update!(user:, label: "Mrs Patel")
    make_kit(path: :helper).update!(user:)
    make_kit.update!(user:, purge_after: 1.day.ago, last_active_at: 40.days.ago)
    make_kit

    sign_in_as(user)
    get account_path

    assert_select "h1", "Your account"
    assert_select ".lead", "Signed in with Google as Rosa Diaz, rosa@example.com."
    assert_select "p", "You have 16 credits. A look on your face uses 2."
    assert_select ".linklist a", 2
    assert_select ".linklist a", /Mrs Patel/
    assert_select ".linklist a", /Kit for someone you help/
    assert_select "a[href=?]", Credits::PRICING_PATH, text: /Get credits/
    assert_select "a[href=?]", delete_account_path, text: /Delete my account/
    assert_select "form[action=?] input[name=_method][value=delete]", sign_out_path
    assert_select "details.menu summary", /Rosa/
  end

  test "one credit is one credit" do
    user = make_user(credits: 1)
    sign_in_as(user)
    get account_path
    assert_select "p", "You have 3 credits. A look on your face uses 2."
    Credits.debit!(user, 2, reason: :admin, source: nil)
    get account_path
    assert_select "p", "You have 1 credit. A look on your face uses 2."
  end

  test "delete my account asks on its own page, then deletes everything at once" do
    user = make_user
    kit = make_kit
    kit.update!(user:)
    sign_in_as(user)

    get delete_account_path
    assert_select "h1", "Delete your account?"
    assert_select "form[action=?] button", account_path, text: /Yes, delete my account/

    delete account_path
    assert_redirected_to root_path
    assert_not User.exists?(user.id)
    assert_not Kit.exists?(kit.id)
    assert_equal 0, CreditEntry.count
    assert_nil session[:user_id]

    delete account_path
    assert_redirected_to root_path
  end

  test "starting a kit while signed in puts it in the account" do
    user = make_user
    sign_in_as(user)

    post start_path, params: { path: "self_use" }
    assert_equal user, Kit.order(:id).last.user
  end
end
