# frozen_string_literal: true

require "test_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "stringio"
require "vips"

class PhotosTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  TaskRun = Struct.new(:output, :aborted) do
    def aborted? = aborted
  end

  setup do
    self.class.load_rake_tasks
    @tmpdirs = []
    @previous_scanner = ENV["PHOTOS_GPS_SCANNER"]
    @previous_workers = ENV["PHOTOS_WORKERS"]
    # exiftool is not installed on every machine; the libvips scanner reads the
    # same EXIF GPS block, so the suite does not hang off an external binary.
    ENV["PHOTOS_GPS_SCANNER"] = "vips"
    ENV["PHOTOS_WORKERS"] = "1"
  end

  teardown do
    ENV["PHOTOS_GPS_SCANNER"] = @previous_scanner
    ENV["PHOTOS_WORKERS"] = @previous_workers
    @tmpdirs.each { |dir| FileUtils.remove_entry(dir, true) }
  end

  # --- ingest ---------------------------------------------------------------

  test "ingest creates one photo per image in sorted filename order" do
    section = section_for
    dir = source_dir(%w[c.jpg a.jpg e.jpg b.jpg d.jpg])

    run = run_task("photos:ingest", "2025", "day-1", dir)

    refute run.aborted?, run.output
    photos = section.photos.reload.order(:position).to_a
    assert_equal %w[a.jpg b.jpg c.jpg d.jpg e.jpg], photos.map(&:original_filename)
    assert_equal [ 1, 2, 3, 4, 5 ], photos.map(&:position)
    assert_equal 5, photos.map(&:source_digest).uniq.compact.size
    assert photos.all? { |photo| photo.image.attached? }
    assert_equal [ [ 480, 320 ] ], photos.map { |photo| [ photo.width, photo.height ] }.uniq
    assert photos.all? { |photo| photo.dominant_color.present? }
    assert_nil photos.first.derivatives_ready_at, "ingest must not mark photos displayable"
    assert_match(/Ingested 5 photo/, run.output)
  end

  test "re-running ingest creates no duplicates and reports the skipped count" do
    section = section_for
    dir = source_dir(%w[a.jpg b.jpg c.jpg d.jpg e.jpg])

    run_task("photos:ingest", "2025", "day-1", dir)
    blobs_after_first = ActiveStorage::Blob.count
    second = run_task("photos:ingest", "2025", "day-1", dir)

    refute second.aborted?, second.output
    assert_equal 5, section.photos.reload.count
    assert_equal blobs_after_first, ActiveStorage::Blob.count, "a re-run uploaded the files again"
    assert_match(/Ingested 0 photo\(s\) into 2025\/day-1, skipped 5/, second.output)
  end

  test "non-image files and dotfiles are skipped with a warning rather than crashing" do
    section = section_for
    dir = source_dir([ "a.jpg", "notes.txt", ".DS_Store", "._b.jpg", "b.jpg" ])
    FileUtils.mkdir_p(File.join(dir, "raw"))

    run = run_task("photos:ingest", "2025", "day-1", dir)

    refute run.aborted?, run.output
    assert_equal %w[a.jpg b.jpg], section.photos.reload.order(:position).map(&:original_filename)
    assert_match(/WARNING: skipping notes\.txt/, run.output)
    assert_match(/WARNING: skipping \.DS_Store \(dotfile\)/, run.output)
    assert_match(/WARNING: skipping \._b\.jpg \(dotfile\)/, run.output)
    assert_match(/WARNING: skipping directory raw/, run.output)
  end

  test "ingest fails with a clear message when the gallery does not exist" do
    section_for
    dir = source_dir(%w[a.jpg])

    run = run_task("photos:ingest", "2024", "day-1", dir)

    assert run.aborted?
    assert_match(/No gallery has the slug "2024"/, run.output)
    assert_match(/Known galleries: 2025/, run.output)
    assert_equal 0, Photo.count
  end

  test "ingest fails with a clear message when the section does not exist" do
    section_for
    dir = source_dir(%w[a.jpg])

    run = run_task("photos:ingest", "2025", "day-9", dir)

    assert run.aborted?
    assert_match(/Gallery "2025" has no section "day-9"/, run.output)
    assert_match(/Its sections: day-1/, run.output)
    assert_equal 0, Photo.count
  end

  test "ingest fails with a clear message when the directory does not exist" do
    section_for

    run = run_task("photos:ingest", "2025", "day-1", "/nope/not/here")

    assert run.aborted?
    assert_match(%r{Directory not found: /nope/not/here}, run.output)
  end

  test "ingest refuses a directory whose sources still carry GPS data" do
    section = section_for
    dir = source_dir(%w[a.jpg b.jpg], gps: %w[b.jpg])

    run = run_task("photos:ingest", "2025", "day-1", dir)

    assert run.aborted?
    assert_match(/1 file\(s\) still carry GPS data/, run.output)
    assert_match(/b\.jpg/, run.output)
    assert_match(/exiftool -gps:all=/, run.output)
    assert_equal 0, section.photos.reload.count, "nothing may be imported when a source carries GPS"
    assert_equal 0, ActiveStorage::Blob.count
  end

  test "ingest refuses to run at all when exiftool is missing" do
    section = section_for
    dir = source_dir(%w[a.jpg])
    ENV.delete("PHOTOS_GPS_SCANNER")

    run = stubbing(PhotoTasks::Gps, :exiftool?, false) do
      run_task("photos:ingest", "2025", "day-1", dir)
    end

    assert run.aborted?
    assert_match(/exiftool is not installed/, run.output)
    assert_match(/brew install exiftool/, run.output)
    assert_equal 0, section.photos.reload.count
  end

  test "ingest uses exiftool for the GPS check when it is available" do
    section = section_for
    dir = source_dir(%w[a.jpg])
    ENV.delete("PHOTOS_GPS_SCANNER")

    run = stubbing(PhotoTasks::Gps, :exiftool?, true) do
      stubbing(PhotoTasks::Gps, :exiftool_tagged, ->(paths) { [ paths.first ] }) do
        run_task("photos:ingest", "2025", "day-1", dir)
      end
    end

    assert run.aborted?
    assert_match(/with exiftool/, run.output)
    assert_match(/still carry GPS data/, run.output)
    assert_equal 0, section.photos.reload.count
  end

  test "ingest does not enqueue a transform job per variant" do
    section_for
    dir = source_dir(%w[a.jpg b.jpg c.jpg d.jpg e.jpg])

    run = nil
    assert_no_enqueued_jobs do
      run = run_task("photos:ingest", "2025", "day-1", dir)
    end


    refute run.aborted?, run.output
    # 5 photos x 9 preprocessed variants would be 45 TransformJobs plus 5
    # AnalyzeJobs in SQLite -- KTD9's failure mode at 1/383rd scale.
    assert_equal 5, Photo.count
    assert Photo.first.image.blob.analyzed?, "the blob should still be analyzed, just inline"
  end

  # --- preprocess -----------------------------------------------------------

  test "preprocess bakes every declared variant and marks the photo ready" do
    section = section_for
    ingest(section, %w[a.jpg b.jpg])

    run = run_task("photos:preprocess", "2025")

    refute run.aborted?, run.output
    photos = section.photos.reload.to_a
    assert_equal 2, photos.size
    photos.each do |photo|
      assert_equal Photo::VARIANTS.keys.sort, baked_variants(photo).sort
      assert photo.derivatives_ready_at.present?, "derivatives_ready_at was not set"
    end
    assert_match(/Baked 18 variant\(s\)/, run.output)
    assert_match(/2 of 2 photo\(s\) have all 9 derivatives/, run.output)
  end

  test "re-running preprocess bakes nothing and is a no-op" do
    section = section_for
    ingest(section, %w[a.jpg])
    run_task("photos:preprocess", "2025")
    records_after_first = ActiveStorage::VariantRecord.count

    second = run_task("photos:preprocess", "2025")

    refute second.aborted?, second.output
    assert_equal records_after_first, ActiveStorage::VariantRecord.count
    assert_match(/Baked 0 variant\(s\).*9 already present/, second.output)
  end

  test "preprocess rebuilds a variant whose file disappeared and runs its worker pool" do
    ENV["PHOTOS_WORKERS"] = "2"
    section = section_for
    ingest(section, %w[a.jpg b.jpg])
    run_task("photos:preprocess", "2025")

    photo = section.photos.reload.first
    blob = variant_blob(photo, :wall_avif)
    blob.service.delete(blob.key)
    refute blob.service.exist?(blob.key)

    run = run_task("photos:preprocess", "2025")

    refute run.aborted?, run.output
    assert_match(/with 2 worker\(s\)/, run.output)
    assert_match(/Baked 1 variant\(s\)/, run.output)
    rebuilt = variant_blob(photo.reload, :wall_avif)
    assert rebuilt.service.exist?(rebuilt.key), "the missing variant file was not rebuilt"
  end

  # --- verify ---------------------------------------------------------------

  test "verify reports nothing missing on a fully baked gallery" do
    section = section_for
    ingest(section, %w[a.jpg])
    run_task("photos:preprocess", "2025")

    run = run_task("photos:verify", "2025")

    refute run.aborted?, run.output
    assert_match(/checked 1 photo\(s\) x 9 variants/, run.output)
    assert_match(/All derivatives present/, run.output)
  end

  test "verify reports a photo whose variant record is missing and does not generate it" do
    section = section_for
    ingest(section, %w[a.jpg])
    run_task("photos:preprocess", "2025")
    photo = section.photos.reload.first
    variant_record(photo, :zoom_avif).destroy
    records_before = ActiveStorage::VariantRecord.count

    run = run_task("photos:verify", "2025")

    assert run.aborted?, "verify must exit non-zero when a derivative is missing"
    assert_match(/missing zoom_avif/, run.output)
    assert_match(/1 photo\(s\) are missing derivatives/, run.output)
    # The whole point: asking for a variant is what builds it, so a verifier
    # that asks can never fail.
    assert_equal records_before, ActiveStorage::VariantRecord.count,
                 "verify generated the variant it was asked to report"
    assert_nil variant_record(photo.reload, :zoom_avif)
  end

  test "verify reports a photo whose variant file was deleted and does not regenerate it" do
    section = section_for
    ingest(section, %w[a.jpg])
    run_task("photos:preprocess", "2025")
    photo = section.photos.reload.first
    photo.update_columns(derivatives_ready_at: Time.current)
    blob = variant_blob(photo, :thumb_webp)
    blob.service.delete(blob.key)

    run = run_task("photos:verify", "2025")

    assert run.aborted?
    assert_match(/file gone for thumb_webp/, run.output)
    assert_match(/ALERT: 1 photo\(s\) are marked ready but are missing derivatives/, run.output)
    refute blob.service.exist?(blob.key), "verify regenerated the file it was asked to report"
  end

  test "verify flags a photo that has every derivative but was never marked ready" do
    section = section_for
    ingest(section, %w[a.jpg])
    run_task("photos:preprocess", "2025")
    section.photos.reload.first.update_columns(derivatives_ready_at: nil)

    run = run_task("photos:verify", "2025")

    refute run.aborted?, run.output
    assert_match(/1 photo\(s\) have every derivative but no derivatives_ready_at/, run.output)
  end

  test "verify fails clearly for an unknown gallery" do
    section_for

    run = run_task("photos:verify", "nope")

    assert run.aborted?
    assert_match(/No gallery has the slug "nope"/, run.output)
  end

  private
    def self.load_rake_tasks
      return if @rake_tasks_loaded

      Rails.application.load_tasks
      @rake_tasks_loaded = true
    end

    def run_task(name, *args)
      task = Rake::Task[name]
      task.reenable
      buffer = StringIO.new
      previous_out, previous_err = $stdout, $stderr
      $stdout = buffer
      $stderr = buffer
      aborted = false
      begin
        task.invoke(*args)
      rescue SystemExit
        aborted = true
      ensure
        $stdout, $stderr = previous_out, previous_err
      end
      TaskRun.new(buffer.string, aborted)
    end

    # Minitest 6 dropped Object#stub with minitest/mock, and these two swaps are
    # the only ones the suite needs.
    def stubbing(object, name, result)
      singleton = object.singleton_class
      original = object.method(name)
      singleton.define_method(name) { |*args| result.respond_to?(:call) ? result.call(*args) : result }
      yield
    ensure
      singleton.define_method(name, original)
    end

    def section_for
      gallery = create_gallery(slug: "2025", sections: { "day-1" => "Day 1" })
      gallery.sections.first
    end

    def ingest(section, names)
      run = run_task("photos:ingest", section.gallery.slug, section.slug, source_dir(names))
      refute run.aborted?, run.output
      section.photos.reload
    end

    # Small synthetic images: nine AVIF/WebP encodes per photo is the slow part
    # of this suite, and 480x320 keeps it honest without keeping it slow.
    def source_dir(names, gps: [])
      dir = Dir.mktmpdir("photos-ingest")
      @tmpdirs << dir
      names.each_with_index do |name, index|
        path = File.join(dir, name)
        if name.start_with?(".") || File.extname(name) != ".jpg"
          File.write(path, "not an image\n")
          next
        end

        image = (Vips::Image.black(480, 320) + (17 * (index + 1))).cast(:uchar)
        image = with_gps(image) if gps.include?(name)
        image.write_to_file(path)
      end
      dir
    end

    def with_gps(image)
      image = image.copy
      image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitudeRef", "N")
      image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitude", "51/1 30/1 30/1")
      image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLongitudeRef", "W")
      image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLongitude", "0/1 7/1 0/1")
      image
    end

    def variant_record(photo, name)
      blob = photo.image.blob
      digest = blob.variant(Photo::VARIANTS.fetch(name)).variation.digest
      ActiveStorage::VariantRecord.find_by(blob_id: blob.id, variation_digest: digest)
    end

    def variant_blob(photo, name)
      variant_record(photo, name).image.blob
    end

    def baked_variants(photo)
      Photo::VARIANTS.keys.select { |name| variant_record(photo, name)&.image&.attached? }
    end
end
