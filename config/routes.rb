Rails.application.routes.draw do
  # No :registerable on the model is what actually removes the sign-up routes;
  # this documents the intent and drops the password paths too.
  devise_for :users, skip: [ :registrations, :passwords ]

  # Inside an authenticate block rather than behind a before_action, so /avo is
  # not even routable when signed out.
  authenticate :user do
    mount_avo
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "galleries#index"

  # Gallery slugs sit at the root, so they must not swallow the reserved
  # prefixes above. Everything below is scoped by that constraint.
  RESERVED = %w[users avo up rails assets active_storage].freeze

  scope ":gallery_slug", constraints: { gallery_slug: /(?!(#{RESERVED.join("|")})\b)[a-z0-9][a-z0-9-]*/ } do
    get "/", to: "galleries#show", as: :gallery

    scope ":section_slug" do
      get "/", to: "sections#show", as: :gallery_section

      scope "photos/:id" do
        get "/", to: "photos#show", as: :gallery_section_photo
        get "download", to: "photos#download", as: :download_gallery_section_photo
      end
    end
  end
end
