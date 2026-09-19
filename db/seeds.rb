# One admin. find_or_create_by! so re-running seeds neither fails nor resets an
# existing password -- rotation is a console operation, not a side effect of
# deploying.
#
# The defaults below are development conveniences. Production has no default:
# a known password on a public box is not a convenience, it is the way in.
if Rails.env.local?
  email = ENV.fetch("ADMIN_EMAIL", "adrian@adrianthedev.com")
  password = ENV.fetch("ADMIN_PASSWORD", "secreto")
else
  email = ENV["ADMIN_EMAIL"]
  password = ENV["ADMIN_PASSWORD"]
end

if email.present? && password.present?
  user = User.find_or_create_by!(email: email) { |u| u.password = password }
  puts "Admin ready: #{user.email}"
else
  abort "Set ADMIN_EMAIL and ADMIN_PASSWORD to seed the admin account."
end
