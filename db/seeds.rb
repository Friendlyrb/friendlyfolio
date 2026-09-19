# One admin, from the environment. find_or_create_by! so re-running seeds
# neither fails nor resets an existing password -- rotation is a console
# operation, not a side effect of deploying.
email = ENV["ADMIN_EMAIL"]
password = ENV["ADMIN_PASSWORD"]

if email.present? && password.present?
  User.find_or_create_by!(email: email) { |u| u.password = password }
  puts "Admin ready: #{email}"
else
  puts "Set ADMIN_EMAIL and ADMIN_PASSWORD to seed the admin account."
end
