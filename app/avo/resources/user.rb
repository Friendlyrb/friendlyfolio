class Avo::Resources::User < Avo::BaseResource
  self.title = :email
  self.icon = "tabler/outline/user-shield"

  # Devise :validatable demands a password on create. Without this, saving any
  # other change to an existing admin would fail for want of one.
  self.devise_password_optional = true

  def fields
    field :id, as: :id
    field :email, as: :text, required: true, link_to_record: true

    # The single admin is seeded from credentials, not created here. The field
    # exists so that admin can change their own password; there is no reset
    # flow, because :recoverable is deliberately off and no mail is configured.
    field :password, as: :password, only_on: :forms,
      help: "Leave blank to keep the current password."
  end
end
