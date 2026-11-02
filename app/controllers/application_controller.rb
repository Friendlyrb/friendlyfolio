class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :admin_signed_in?

  private

  def admin_signed_in? = user_signed_in?

  # Public pages may be cached at the edge; anything rendered for a signed-in
  # admin must not be. The same URL renders differently for an admin, so
  # without this the first admin preview of an unpublished gallery would
  # populate the CDN with the page publication exists to hide.
  #
  # A flash is per-visitor too (the "Signed out" notice lands on the public
  # index), so a response carrying one stays private. Otherwise anonymous
  # responses skip the session, so a shared cache never stores a Set-Cookie.
  #
  # Section and photo URLs answer Turbo frame requests with only the wall, so
  # the cache key has to include that header.
  def set_cache_headers
    response.headers["Vary"] = [ response.headers["Vary"], "Turbo-Frame" ].compact.join(", ")

    if user_signed_in? || flash.any?
      response.headers["Cache-Control"] = "private, no-store"
    else
      request.session_options[:skip] = true
      # The CDN keeps a page for five minutes; browsers revalidate on every
      # visit (a cheap 304 through the ETag). Letting browsers keep it too
      # meant that after signing in or out, the redirect to a public page
      # showed the copy from before -- no flash, and the old session's view.
      expires_in 0, public: true, "s-maxage": 5.minutes.to_i
    end
  end
end
