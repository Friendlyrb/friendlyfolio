# The edition touches friendlyrb.com puts on its own edition pages: a
# handwritten "Edition three", and the year drawn in the logo's pixel style.
module EditionHelper
  # The 5x7 digit font friendlyrb.com draws its years in (_data/pixel_digits.json there).
  PIXEL_DIGITS = JSON.parse(File.read(Rails.root.join("config/pixel_digits.json"))).freeze
  ORDINALS = %w[one two three four five six seven eight nine].freeze
  NUMBERS = %w[zero one two three four five six seven eight nine ten].freeze

  # Small counts read as words in headings ("Three editions"); larger ones as digits.
  def number_in_words(count) = NUMBERS[count] || count.to_s

  # Editions count from the first year friendlyrb.com has a colour for, so a
  # gallery that is not an edition (a meetup, a workshop) gets no label.
  def edition_label(gallery)
    index = ApplicationHelper::EDITION_ACCENTS.keys.sort.index(gallery.held_on&.year)
    "Edition #{ORDINALS[index]}" if index
  end

  # "Friendly.rb 2025" splits into the name and a year to draw in pixels.
  # Titles that do not end in their own year are left whole.
  def edition_title_parts(gallery)
    year = gallery.held_on&.year.to_s
    return [ gallery.title, nil ] if year.blank? || !gallery.title.end_with?(" #{year}")

    [ gallery.title.delete_suffix(" #{year}"), year ]
  end

  # Each pixel carries its column and row, so the stylesheet can drop them in
  # one by one, left to right, as friendlyrb.com does. Decorative: the year is
  # always in the text beside it.
  def pixel_year(year, class_name: nil)
    digits = year.to_s.chars
    bits = digits.each_with_index.flat_map do |digit, d|
      PIXEL_DIGITS.fetch(digit).each_with_index.flat_map do |row, y|
        row.chars.each_with_index.filter_map { |bit, x| [ (d * 6) + x, y ] if bit == "1" }
      end
    end

    pixels = bits.map do |x, y|
      tag.g(class: "pixel-bit", style: "--c: #{x}; --r: #{y}; --dx: #{(x % 3) - 1}") do
        tag.rect(class: "pixel-shadow", x: x + 0.35, y: y + 0.35, width: 1.02, height: 1.02) +
          tag.rect(class: "pixel-face", x: x, y: y, width: 1.02, height: 1.02)
      end
    end

    tag.svg(safe_join(pixels), class: [ "pixel-year", class_name ],
            viewBox: "0 0 #{(digits.size * 6) - 1}.35 7.35", "shape-rendering": "crispEdges",
            "aria-hidden": "true", focusable: "false")
  end

  # The cover in front, then two more from anywhere in the gallery. Random, so
  # a return visit shows different moments; the CDN keeps each pick for its
  # five minutes, which is plenty of variety.
  def hero_polaroids(gallery)
    cover = gallery.cover or return []
    others = gallery.photos.displayable.with_images.includes(section: :gallery)
                    .where.not(id: cover.id).reorder(Arel.sql("RANDOM()")).limit(2)
    [ cover, *others ]
  end

  # A polaroid's handwritten caption: where in the edition it was taken.
  def polaroid_caption(photo)
    year = photo.section.gallery.held_on&.year
    [ photo.section.title, year ].compact.join(", ")
  end
end
