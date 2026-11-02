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

  test "signing out shows the notice as a dismissible status card" do
    User.find_or_create_by!(email: "adrian@adrianthedev.com") { |u| u.password = "secreto" }
    post user_session_path, params: { user: { email: "adrian@adrianthedev.com", password: "secreto" } }

    delete destroy_user_session_path
    follow_redirect!

    card = response.body[%r{<div class="flash flash--notice".*?</div>}m]
    assert card, "the notice should render as a flash card"
    assert_match(/role="status"/, card)
    assert_match(/data-flash-dismiss-after-value="6000"/, card)
    assert_match(/Signed out successfully\./, card)
    assert_match(/aria-label="Dismiss message"/, card)
  end

  test "a failed sign-in shows an alert card that stays" do
    post user_session_path, params: { user: { email: "adrian@adrianthedev.com", password: "wrong" } }

    card = response.body[%r{<div class="flash flash--alert".*?</div>}m]
    assert card, "the alert should render as a flash card"
    assert_match(/role="alert"/, card)
    assert_no_match(/dismiss-after/, card, "an error must not vanish on a timer")
    assert_match(/That email and password do not match\./, card)
  end

  test "sign-up does not exist" do
    get "/users/sign_up"

    assert_response :not_found
  end
end
