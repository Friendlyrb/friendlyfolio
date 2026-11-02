# Be sure to restart your server when you modify this file.

# Scripts only from this origin (plus the nonce-tagged importmap tags), so a
# string that ever reaches HTML unescaped -- the admin importer once put dropped
# folder names into innerHTML -- cannot run as script.
#
# Images may come from the R2 public host (R2_PUBLIC_HOST, see
# ApplicationHelper#photo_variant_url), and the admin importer PUTs direct
# uploads straight to the R2 endpoint. Styles keep 'unsafe-inline': the wall
# sizes every tile with a style attribute, and Turbo injects its progress bar.
Rails.application.configure do
  image_host = ENV["R2_PUBLIC_HOST"].presence
  r2_endpoint = ("https://#{ENV["R2_ACCOUNT_ID"]}.r2.cloudflarestorage.com" if ENV["R2_ACCOUNT_ID"].present?)

  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.script_src      :self
    policy.style_src       :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src        :self, :data, "https://fonts.gstatic.com"
    policy.img_src         :self, :data, :blob, *[ image_host, r2_endpoint ].compact
    policy.connect_src     :self, *[ r2_endpoint ].compact
    policy.object_src      :none
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :self
  end

  # Random per response rather than the session id: public pages skip the
  # session. A cached page and its header share one nonce, so caching is fine.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
