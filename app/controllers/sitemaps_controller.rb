class SitemapsController < ApplicationController
  # Built from Gallery.published whoever asks, so the output never differs for
  # an admin and can be cached publicly like the pages it lists.
  def show
    @galleries = Gallery.published.newest_first.includes(:sections)
    expires_in 1.hour, public: true
  end

  # Served by the app rather than from public/, because the Sitemap line must
  # be an absolute URL on the configured host.
  def robots
    expires_in 1.day, public: true
    render plain: <<~ROBOTS
      User-agent: *
      Disallow: /avo
      Disallow: /users
      Allow: /

      Sitemap: #{helpers.absolute_url("/sitemap.xml")}
    ROBOTS
  end
end
