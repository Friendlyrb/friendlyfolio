ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    parallelize(workers: :number_of_processors)
    fixtures :all

    # Attaches a real image and marks the photo bakeable, because the public
    # scopes require derivatives_ready_at.
    def create_photo(section, position: 1, fixture: "landscape.jpg", ready: true)
      photo = Photo.without_auto_bake { section.photos.create!(position: position) }
      photo.image.attach(
        io: File.open(Rails.root.join("test/fixtures/files", fixture)),
        filename: fixture,
        content_type: "image/jpeg"
      )
      photo.extract_image_metadata
      photo.update!(derivatives_ready_at: Time.current) if ready
      photo.reload
    end

    def create_gallery(slug: "2025", published: true, sections: { "day-1" => "Day 1" })
      gallery = Gallery.create!(slug: slug, title: "Friendly.rb #{slug}", held_on: Date.new(2025, 9, 10),
                                published_at: (published ? Time.current : nil))
      sections.each_with_index do |(s, title), i|
        gallery.sections.create!(slug: s, title: title, position: i + 1)
      end
      gallery
    end
  end
end
