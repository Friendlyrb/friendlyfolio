# One admin account on the public internet, with the whole admin surface behind
# it and no lockout, is a password-guessing target nothing else here mitigates.
class Rack::Attack
  throttle("logins/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end
end
