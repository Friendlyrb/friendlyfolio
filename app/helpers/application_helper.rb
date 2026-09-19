module ApplicationHelper
  # Proxy-mode URL: permanent, and already carrying a long-lived public
  # Cache-Control from Rails, which is what lets a CDN hold it indefinitely.
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
