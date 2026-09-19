class User < ApplicationRecord
  # One admin, seeded from the environment. No :registerable (which is what
  # actually removes the sign-up routes), no :recoverable (no mail delivery
  # configured), no :trackable (nothing reads sign-in statistics).
  devise :database_authenticatable, :rememberable, :validatable
end
