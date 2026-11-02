# Search and social metadata, matching what friendlyrb.com's layout emits.
#
# Views declare their values with `seo title: ..., description: ...` rather
# than content_for: content_for escapes on the way in, so a title that later
# lands in an attribute or in JSON-LD came out escaped twice.
module SeoHelper
  SITE_NAME = "Friendly.rb Photos".freeze
  TAGLINE = "Photos from every Friendly.rb Conf edition".freeze
  DEFAULT_DESCRIPTION = "Photo galleries from Friendly.rb Conf, the friendly European Ruby " \
                        "conference held in Bucharest from 2023 to 2025.".freeze
  DEFAULT_ROBOTS = "index, follow, max-image-preview:large".freeze

  # The conference site's own Organization node, by the same @id, so search
  # engines read both sites as one publisher.
  CONFERENCE_URL = "https://friendlyrb.com/".freeze
  ORGANIZATION = {
    "@type" => "Organization",
    "@id" => "https://friendlyrb.com/#organization",
    "name" => "Friendly.rb Conf",
    "url" => CONFERENCE_URL,
    "logo" => "https://friendlyrb.com/assets/images/brand/icon-512.png",
    "email" => "hi@friendlyrb.com",
    "sameAs" => [
      "https://twitter.com/friendlyrb",
      "https://ruby.social/@friendlyrb",
      "https://www.youtube.com/@friendlyrb",
      "https://friendlyrb.com"
    ]
  }.freeze

  # share_jpeg is resized to fit 2048px, and unfurlers want its real size.
  SHARE_LIMIT = 2048

  def seo(**values)
    (@seo ||= {}).merge!(values.compact)
    nil
  end

  def seo_value(key) = @seo&.dig(key)

  def page_title
    title = seo_value(:title)
    title.present? ? "#{title} | #{SITE_NAME}" : "#{SITE_NAME} — #{TAGLINE}"
  end

  def meta_description
    (seo_value(:description).presence || DEFAULT_DESCRIPTION).squish.truncate(160)
  end

  def meta_robots = seo_value(:robots) || DEFAULT_ROBOTS

  # Absolute URLs come from the configured public host, never from the request:
  # Host and X-Forwarded-Host are client-controlled, and these tags sit in
  # responses that edge caches may share. Without APP_HOST (development, test)
  # the request is all there is.
  def site_base_url
    Rails.configuration.x.canonical_url.presence || request.base_url
  end

  # Concatenation, not URI.join: URI.join reads a path beginning "//" as a
  # network-path reference and swaps the host. Absolute URLs pass through only
  # because photo_variant_url returns them for the image host.
  def absolute_url(path_or_url)
    return path_or_url if path_or_url.match?(%r{\Ahttps?://}i)

    "#{site_base_url.chomp("/")}/#{path_or_url.sub(%r{\A/+}, "")}"
  end

  # From the route, never request.path: the router collapses "//2025" to the
  # /2025 gallery, but request.path keeps the slashes.
  def canonical_url = absolute_url(seo_value(:canonical_path) || url_for(only_path: true))

  def og_image
    photo = seo_value(:image) or return
    scale = [ SHARE_LIMIT.fdiv([ photo.width.to_i, photo.height.to_i, 1 ].max), 1 ].min

    {
      url: absolute_url(photo_variant_url(photo, :share_jpeg)),
      width: (photo.width.to_i * scale).round.nonzero?,
      height: (photo.height.to_i * scale).round.nonzero?,
      alt: seo_value(:image_alt)
    }
  end

  def structured_data
    website_id = absolute_url("/#website")
    page = {
      "@type" => seo_value(:page_type) || "WebPage",
      "@id" => canonical_url,
      "url" => canonical_url,
      "name" => page_title,
      "description" => meta_description,
      "inLanguage" => "en",
      "isPartOf" => { "@id" => website_id },
      "primaryImageOfPage" => og_image&.dig(:url)
    }.compact

    graph = [
      ORGANIZATION,
      {
        "@type" => "WebSite",
        "@id" => website_id,
        "url" => absolute_url("/"),
        "name" => SITE_NAME,
        "description" => DEFAULT_DESCRIPTION,
        "inLanguage" => "en",
        "publisher" => { "@id" => ORGANIZATION["@id"] }
      },
      page
    ]

    if (crumbs = seo_value(:breadcrumbs)).present?
      graph << {
        "@type" => "BreadcrumbList",
        "itemListElement" => crumbs.each_with_index.map do |(name, path), i|
          { "@type" => "ListItem", "position" => i + 1, "name" => name, "item" => absolute_url(path) }
        end
      }
    end

    # to_json escapes <, > and & as < etc., so stored titles cannot close
    # the script element.
    tag.script({ "@context" => "https://schema.org", "@graph" => graph }.to_json.html_safe, type: "application/ld+json")
  end
end
