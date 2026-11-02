module Users
  # Sign-in limits enforced on the routed action itself, so they hold whatever
  # path spelling or body encoding a request uses. Rack::Attack in front only
  # sheds floods early.
  #
  # An in-process store on purpose: Puma runs one process here
  # (config/puma.rb), and failed logins have no business writing to the cache
  # database. A restart resets the counters, which is acceptable.
  class SessionsController < Devise::SessionsController
    LOGIN_ATTEMPTS = ActiveSupport::Cache::MemoryStore.new

    rate_limit to: 10, within: 1.minute, only: :create, store: LOGIN_ATTEMPTS, name: "ip"
    rate_limit to: 10, within: 10.minutes, only: :create, store: LOGIN_ATTEMPTS, name: "email",
               by: -> { params.dig(:user, :email).to_s.downcase.strip }
  end
end
