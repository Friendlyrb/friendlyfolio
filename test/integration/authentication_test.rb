require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "the development sign-in form is pre-filled with the seeded admin" do
    get new_user_session_path

    assert_response :success
    assert_match(/value="adrian@adrianthedev\.com"/, response.body)
    assert_match(/value="secreto"/, response.body)
  end

  test "correct credentials sign in" do
    User.find_or_create_by!(email: "adrian@adrianthedev.com") { |u| u.password = "secreto" }

    post user_session_path, params: { user: { email: "adrian@adrianthedev.com", password: "secreto" } }

    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "incorrect credentials re-render at a status Turbo displays" do
    post user_session_path, params: { user: { email: "adrian@adrianthedev.com", password: "wrong" } }

    assert_response :unprocessable_content
  end

  test "sign-up does not exist" do
    get "/users/sign_up"

    assert_response :not_found
  end
end
