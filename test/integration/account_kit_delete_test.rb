require "test_helper"
require "support/kit_helpers"
require "support/account_helpers"

# Deleting: a second "delete my account" says what happened, and a kit in an account is deleted only by its owner.
class AccountKitDeleteTest < ActionDispatch::IntegrationTest
  include KitHelpers
  include AccountHelpers

  test "delete my account while signed out says so, and deletes nothing" do
    user = make_user

    delete account_path

    assert_redirected_to root_path
    assert_equal "You're signed out.", flash[:notice]
    assert User.exists?(user.id)
  end

  test "a kit in an account can't be deleted with its link alone" do
    owner = make_user
    kit = make_kit
    kit.update!(user: owner)

    get delete_kit_path(kit)
    assert_includes response.body, "Sign in with that account to delete it."
    assert_select "form[action=?] input[name=_method][value=delete]", kit_path(kit), count: 0

    delete kit_path(kit)
    assert_redirected_to kit_path(kit)
    assert Kit.exists?(kit.id)

    sign_in_as(make_user(name: "Someone Else"))
    delete kit_path(kit)
    assert Kit.exists?(kit.id)
  end

  test "its owner, signed in, deletes it" do
    owner = make_user
    kit = make_kit
    kit.update!(user: owner)
    sign_in_as(owner)

    delete kit_path(kit)

    assert_redirected_to root_path
    assert_not Kit.exists?(kit.id)
  end

  test "a guest kit is still deleted with its link" do
    kit = make_kit

    delete kit_path(kit)

    assert_not Kit.exists?(kit.id)
  end
end
