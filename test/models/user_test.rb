require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "the seeded development admin can sign in with its password" do
    user = User.find_or_create_by!(email: "seed@example.com") { |u| u.password = "secreto" }

    assert user.valid_password?("secreto")
    assert_not user.valid_password?("wrong")
  end

  test "seeding twice neither fails nor resets an existing password" do
    User.create!(email: "twice@example.com", password: "original-password")

    assert_no_difference "User.count" do
      User.find_or_create_by!(email: "twice@example.com") { |u| u.password = "different" }
    end

    assert User.find_by(email: "twice@example.com").valid_password?("original-password"),
           "re-seeding must not rotate a password out from under someone"
  end

  test "registerable is not enabled, so nothing can sign itself up" do
    assert_not User.devise_modules.include?(:registerable)
    assert_not User.devise_modules.include?(:recoverable)
  end
end
