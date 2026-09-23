module ApplicationHelper
  # Proxy URLs carry the original's file extension, so Cloudflare treats them
  # as cacheable by default, and Rails answers them with a permanent public
  # Cache-Control and no session cookie. Building one reads nothing but the
  # blob, so a wall needs no variant records loaded.
  def photo_variant_url(photo, variant)
    rails_storage_proxy_path(photo.image.variant(variant))
  end

  # A lazily-loaded Turbo frame is zero-height until it arrives. Without a
  # reservation, every section that loads shoves the page down -- the exact
  # layout shift the wall is built to avoid.
  def reserved_height(section)
    rendered = [ section.photos_count, Section::PER_PAGE ].min
    rows = (rendered / 4.0).ceil
    [ rows * 244, 200 ].max
  end

  def page_title
    [ content_for(:title), "Friendly.rb photos" ].compact.uniq.join(" — ")
  end
end
