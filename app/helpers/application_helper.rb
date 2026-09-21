module ApplicationHelper
  # The fastest URL is the one that never reaches Rails: the object's own key on
  # the CDN-fronted bucket domain. #key reads the variant record and never
  # builds a variant -- unlike #processed, #url and #download -- so this stays
  # off the generation path even if a derivative is somehow missing. A nil key
  # means exactly that, and falls back to the proxy, which does generate it.
  #
  # Without an image host (development, and any deploy where the env var is
  # unset) every URL is the proxy path, so the app works unchanged on disk.
  def photo_variant_url(photo, variant)
    representation = photo.image.variant(variant)
    host = Rails.configuration.x.image_host
    key = representation.key if host.present?

    key.present? ? "#{host}/#{key}" : rails_storage_proxy_path(representation)
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
