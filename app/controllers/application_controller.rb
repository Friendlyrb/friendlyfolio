class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :set_cache_headers

  helper_method :admin_signed_in?

  private

  def admin_signed_in? = user_signed_in?

  # Public pages may be cached at the edge; anything rendered for a signed-in
  # admin must not be. The same URL renders differently for an admin, so
  # without this the first admin preview of an unpublished gallery would
  # populate the CDN with the page publication exists to hide.
  def set_cache_headers
    if user_signed_in?
      response.headers["Cache-Control"] = "private, no-store"
    else
      expires_in 5.minutes, public: true
    end
  end
end
