# One admin account on the public internet, with the whole admin surface behind
# it and no lockout, is a password-guessing target nothing else here mitigates.
#
# This is the early, cheap layer: it turns floods away before Devise runs
# bcrypt. The authoritative per-IP and per-account limits live in
# Users::SessionsController, after routing and parameter parsing, where no
# path or body encoding can route around them.
class Rack::Attack
  SIGN_IN = %r{\A/users/sign_in(?:\.[^/]*)?\z}

  throttle("logins/ip", limit: 10, period: 1.minute) do |req|
    path = req.path.squeeze("/").chomp("/")
    req.ip if req.post? && path.match?(SIGN_IN)
  end
end
