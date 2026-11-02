# One admin account on the public internet, with the whole admin surface behind
# it and no lockout, is a password-guessing target nothing else here mitigates.
#
# The pattern takes any extension, not just the exact path: Devise routes
# /users/sign_in.html to the same action, and an exact match left it uncounted
# (CSRF happened to block it, which is not something this should rely on).
class Rack::Attack
  SIGN_IN = %r{\A/users/sign_in(?:\.[^/]*)?\z}

  throttle("logins/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && req.path.match?(SIGN_IN)
  end

  # Per account as well, so guesses spread across many addresses -- or behind
  # one shared proxy address -- still run out.
  throttle("logins/email", limit: 10, period: 10.minutes) do |req|
    if req.post? && req.path.match?(SIGN_IN)
      req.params.dig("user", "email").to_s.downcase.strip.presence
    end
  end
end
