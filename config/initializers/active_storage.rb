Rails.application.configure do
  # libvips is faster and far lighter on memory than ImageMagick for the
  # resize-heavy work this app does.
  config.active_storage.variant_processor = :vips

  # Without these, Active Storage force-converts variants it does not consider
  # "web images" to PNG -- which would silently defeat the entire AVIF/WebP
  # pipeline.
  config.active_storage.web_image_content_types = %w[
    image/png image/jpeg image/gif image/webp image/avif
  ]

  # Proxy mode gives permanent, cacheable URLs that a CDN can hold forever.
  # Redirect mode is used explicitly for downloads (see PhotosController), where
  # streaming a large original would pin a Puma thread.
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # Deliberately NOT set: config.active_storage.urls_expire_in.
  # An expiry makes every render emit a different URL, which means zero cache
  # hits and a CDN full of URLs that later 404. Leave it nil.
end
