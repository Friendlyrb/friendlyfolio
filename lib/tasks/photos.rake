# frozen_string_literal: true

# Bulk ingest and derivative pre-generation.
#
# RUNBOOK -- the steps are separate on purpose.
#
#   1. Strip GPS from the source files. This mutates the photographer's
#      originals, so it is a deliberate act, not something ingest does behind
#      your back (KTD11):
#
#        exiftool -gps:all= -overwrite_original_in_place -r ~/photos/2025/day-1
#
#      photos:ingest refuses to attach a file that still carries a GPS block,
#      so skipping this step fails loudly rather than publishing attendee
#      locations inside the file the download button hands out.
#
#   2. Ingest one directory into one section:
#
#        bin/rails "photos:ingest[2025,day-1,$HOME/photos/2025/day-1]"
#
#   3. Bake every derivative -- locally, not on the box (KTD15):
#
#        bin/rails "photos:preprocess[2025]"
#
#      Measured on a 10-core M-series laptop against 6000x4000 sources: 12.3s
#      per photo for all nine variants, so the 1,916-photo corpus is roughly
#      6.5 hours. Start it and leave it; it is restartable. Two thirds of that
#      is AVIF encoding and large_avif alone is 6s of it, so the variant ladder
#      (KTD8) is the lever if that is too slow.
#
#   4. Check before publishing. This is the gate:
#
#        bin/rails "photos:verify[2025]"
#
#   5. rsync BOTH halves to the server: storage/files (the bytes) and
#      storage/db (the rows describing them). Copying only the files gives a
#      server that cannot see any of them (KTD15). The initial import replaces
#      the production database; a later one must not.

require "digest"
require "open3"

module PhotoTasks
  # Extension allowlist and the content type recorded for each. Ingest does not
  # sniff (`identify: false`): these are a photographer's exports, and
  # identifying 1,916 of them means reading the head of every file again.
  CONTENT_TYPES = {
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp",
    ".avif" => "image/avif",
    ".tif" => "image/tiff",
    ".tiff" => "image/tiff",
    ".heic" => "image/heic",
    ".heif" => "image/heif"
  }.freeze

  # Active Storage enqueues one TransformJob per preprocessed variant and one
  # AnalyzeJob the moment an attachment commits. Nine variants across 1,916
  # photos is ~17,250 jobs pushed into SQLite while the ingest is still
  # inserting (KTD9). The bulk bake is photos:preprocess, which calls
  # `.processed` directly, so ingest refuses those enqueues rather than queueing
  # work it is about to do itself, and analyzes inline instead of leaving 1,916
  # analyze jobs in a queue database that gets rsynced to the box and dequeued
  # there.
  #
  # The halt is a before_enqueue callback rather than a swapped queue adapter,
  # because a swapped adapter is not honoured under ActiveJob::TestHelper -- its
  # test adapter wins over any assignment -- and a guard that silently stops
  # working in the test suite is exactly the guard this one has to be.
  # BakePhotoVariantsJob is ours: the model enqueues one per attach so a single
  # admin upload gets baked in the background. The bulk path bakes inline, so it
  # suppresses that too rather than queueing 1,916 jobs it is about to do itself.
  SUPPRESSED_JOBS = [
    "ActiveStorage::TransformJob",
    "ActiveStorage::AnalyzeJob",
    "BakePhotoVariantsJob"
  ].freeze
  SUPPRESSION_KEY = :photo_tasks_suppress_active_storage_jobs

  module_function

  # --- entry points ---------------------------------------------------------

  def ingest(gallery_slug, section_slug, directory)
    gallery = find_gallery!(gallery_slug)
    section = find_section!(gallery, section_slug)
    dir = directory.to_s
    die("photos:ingest needs a directory: photos:ingest[gallery,section,/path/to/photos]") if dir.empty?
    die("Directory not found: #{dir}") unless File.directory?(dir)

    paths = image_paths(dir)
    die("No images found in #{dir}. Known extensions: #{CONTENT_TYPES.keys.join(' ')}") if paths.empty?

    assert_gps_free!(paths, dir)

    started = clock
    created = 0
    skipped = 0
    seen = {}

    say "Ingesting #{paths.size} image(s) into #{gallery.slug}/#{section.slug}."

    without_active_storage_jobs do
      paths.each_with_index do |path, index|
        name = File.basename(path)
        digest = Digest::SHA256.file(path).hexdigest

        if (twin = seen[digest])
          say "  WARNING: #{name} is byte-identical to #{twin}; skipping the copy."
          skipped += 1
          next
        end
        seen[digest] = name

        if section.photos.exists?(source_digest: digest)
          skipped += 1
          next
        end

        begin
          # Position comes from the sorted listing, so a resumed run lands every
          # file where the first run would have. Photos already in the section
          # are left alone -- an admin may have reordered them by hand.
          attach(section, path, position: index + 1, digest: digest)
          created += 1
        rescue ActiveRecord::RecordNotUnique
          skipped += 1
        end

        say "  #{index + 1}/#{paths.size} (#{created} new, #{skipped} skipped)" if ((index + 1) % 25).zero?
      end
    end

    say "Ingested #{created} photo(s) into #{gallery.slug}/#{section.slug}, skipped #{skipped}, in #{duration(clock - started)}."
    say "Derivatives are not baked yet. Next: bin/rails \"photos:preprocess[#{gallery.slug}]\""
  end

  def preprocess(gallery_slug)
    gallery = find_gallery!(gallery_slug)
    ids = photo_ids(gallery)
    die("Gallery #{gallery.slug.inspect} has no photos yet.") if ids.empty?

    workers = worker_count
    total = ids.size
    say "Baking #{Photo::VARIANTS.size} variants for #{total} photo(s) in #{gallery.slug} with #{workers} worker(s)."
    say "VIPS_CONCURRENCY=#{ENV['VIPS_CONCURRENCY'] || '(libvips default)'}. Set PHOTOS_WORKERS to change the pool."

    queue = Queue.new
    ids.each { |id| queue << id }
    workers.times { queue << :stop }

    mutex = Mutex.new
    started = clock
    done = 0
    baked = 0
    untouched = 0
    ready = 0
    failures = []

    Array.new(workers) {
      Thread.new do
        loop do
          id = queue.pop
          break if id == :stop

          photo_started = clock
          result =
            begin
              ActiveRecord::Base.connection_pool.with_connection { bake(id) }
            rescue StandardError => e
              { error: e }
            end
          elapsed = clock - photo_started

          mutex.synchronize do
            done += 1
            if (error = result[:error])
              failures << "photo ##{id}: #{error.class}: #{error.message}"
              say "  [#{done}/#{total}] photo ##{id} FAILED: #{error.class}: #{error.message}"
              next
            end

            baked += result[:baked]
            untouched += result[:present]
            ready += 1 if result[:ready]

            if result[:baked].positive? || (done % 50).zero? || done == total
              remaining = total - done
              eta = remaining.positive? ? ", eta #{duration((clock - started) / done * remaining)}" : ""
              say "  [#{done}/#{total}] #{result[:label]} baked #{result[:baked]}, had #{result[:present]} " \
                  "(#{format('%.1fs', elapsed)}, #{remaining} left#{eta})"
            end
          end
        end
      end
    }.each(&:join)

    elapsed = clock - started
    say "Baked #{baked} variant(s) in #{duration(elapsed)} (#{untouched} already present, #{failures.size} failed)."
    say "Per photo: #{format('%.2fs', elapsed / [ total, 1 ].max)} wall clock across #{workers} worker(s)." if total.positive?
    say "#{ready} of #{total} photo(s) have all #{Photo::VARIANTS.size} derivatives and are marked ready."

    if failures.any?
      failures.first(20).each { |f| $stderr.puts "  #{f}" }
      die("#{failures.size} photo(s) failed to bake.")
    end

    say "Next: bin/rails \"photos:verify[#{gallery.slug}]\""
  end

  def verify(gallery_slug)
    gallery = find_gallery!(gallery_slug)
    rows = []
    checked = 0
    live_and_broken = 0
    complete_but_hidden = 0

    gallery_photos(gallery).find_each(batch_size: 200) do |photo|
      checked += 1
      problems = photo_problems(photo)

      if problems.any?
        live_and_broken += 1 if photo.derivatives_ready_at.present?
        rows << [ photo.section.position, photo.position, photo.id,
                  "#{photo.section.slug}/#{photo.download_filename} (##{photo.id}): #{problems.join(', ')}" ]
      elsif photo.derivatives_ready_at.nil?
        complete_but_hidden += 1
      end
    end

    say "#{gallery.slug}: checked #{checked} photo(s) x #{Photo::VARIANTS.size} variants."

    rows.sort_by { |r| r.first(3) }.each { |r| say "  #{r.last}" }

    if complete_but_hidden.positive?
      say "  NOTE: #{complete_but_hidden} photo(s) have every derivative but no derivatives_ready_at, " \
          "so they will not render. Re-run photos:preprocess."
    end

    if live_and_broken.positive?
      say "  ALERT: #{live_and_broken} photo(s) are marked ready but are missing derivatives. " \
          "They are live, and a visitor will generate those variants inside a web request (KTD9)."
    end

    if rows.any?
      die("#{rows.size} photo(s) are missing derivatives. Run: bin/rails \"photos:preprocess[#{gallery.slug}]\"")
    end

    say "All derivatives present. #{gallery.slug} is safe to publish."
  end

  # --- variant existence ----------------------------------------------------

  # The verifier's whole point: answer "does this variant exist?" from the
  # stored record and the file on the service, and never construct an
  # ActiveStorage::Variant. #processed, #url, #download and #key all generate a
  # missing variant on demand, so a verifier built on any of them silently
  # repairs what it was asked to report and can never fail.
  def variant_state(blob, transformations)
    record = variant_record(blob, variation_digest(blob, transformations))
    return :missing if record.nil?
    return :stale unless record.image.attached?

    image = record.image.blob
    image.service.exist?(image.key) ? :ok : :stale
  end

  def variant_record(blob, digest)
    if blob.variant_records.loaded?
      blob.variant_records.find { |record| record.variation_digest == digest }
    else
      blob.variant_records.find_by(variation_digest: digest)
    end
  end

  # The digest is not computable from the declared transformations alone:
  # Blob#variant reverse-merges a default format derived from the blob itself,
  # which reorders the hash, and the digest is a Marshal dump. So build the
  # variation the way Active Storage builds it and throw the variant object
  # away. Constructing one is inert -- #processed, #url, #key and #download are
  # the methods that generate a missing variant -- and this is the only line in
  # the file that goes anywhere near a variant object outside the bake.
  def variation_digest(blob, transformations)
    blob.variant(transformations).variation.digest
  end

  # --- internals ------------------------------------------------------------

  def attach(section, path, position:, digest:)
    name = File.basename(path)
    content_type = CONTENT_TYPES.fetch(File.extname(name).downcase)

    # An open handle, not File.read: Active Storage streams it through to the
    # service and hashes it in chunks. Buffering several 24-megapixel files is
    # the way this task runs a machine out of memory.
    blob = File.open(path, "rb") do |file|
      ActiveStorage::Blob.create_and_upload!(
        io: file, filename: name, content_type: content_type, identify: false
      )
    end

    # Inline, because the bake happens on a laptop and the database travels to
    # the box (KTD15). A queued AnalyzeJob would be dequeued on production and
    # pull every original back out of storage to read its header.
    blob.analyze unless blob.analyzed?

    photo = section.photos.new(position: position, original_filename: name, source_digest: digest)
    photo.image.attach(blob)
    photo.save!
    photo
  end

  def bake(id)
    photo = Photo.find(id)
    label = "#{photo.section.slug}/#{photo.download_filename}"
    return { baked: 0, present: 0, ready: false, label: "#{label} (no image attached)" } unless photo.image.attached?

    blob = photo.image.blob
    baked = 0
    present = 0

    Photo::VARIANTS.each do |name, transformations|
      case variant_state(blob, transformations)
      when :ok
        present += 1
      when :stale
        # The row claims the variant exists but its file does not -- a half
        # copied storage tree, or a purged directory. `.processed` trusts the
        # row and would skip it, so drop the row first.
        retrying_writes(label) do
          variant_record(blob, variation_digest(blob, transformations))&.destroy
          photo.image.variant(name).processed
        end
        baked += 1
      else
        retrying_writes(label) { photo.image.variant(name).processed }
        baked += 1
      end
    end

    # Re-read rather than trusting the loop: this is what decides whether the
    # photo becomes visible.
    complete = Photo::VARIANTS.all? { |_name, transformations| variant_state(blob, transformations) == :ok }
    retrying_writes(label) do
      if complete && photo.derivatives_ready_at.nil?
        photo.update_columns(derivatives_ready_at: Time.current, updated_at: Time.current)
      elsif !complete && photo.derivatives_ready_at.present?
        photo.update_columns(derivatives_ready_at: nil, updated_at: Time.current)
      end
    end

    { baked: baked, present: present, ready: complete, label: label }
  end

  # Every worker writes three rows per variant -- variant record, blob,
  # attachment -- and SQLite takes one writer at a time. A deferred transaction
  # that has already read and then tries to upgrade gets SQLITE_BUSY straight
  # away, without the busy handler waiting at all, so raising the pool size
  # without this loses whole photos. Measured: 4 workers dropped 3 of 4 photos
  # before this existed. Retrying costs a repeated transform, which is why the
  # pool stays small rather than leaning on the retries.
  def retrying_writes(label, attempts: 5)
    tries = 0
    begin
      yield
    rescue ActiveRecord::StatementTimeout, ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked => e
      tries += 1
      raise if tries >= attempts

      sleep(0.1 * (2**tries) * (0.5 + rand))
      say "  retrying #{label} after #{e.class} (attempt #{tries + 1} of #{attempts})"
      retry
    end
  end

  def photo_problems(photo)
    return [ "no image attached" ] unless photo.image.attached?

    blob = photo.image.blob
    missing = []
    stale = []
    Photo::VARIANTS.each_key do |name|
      case variant_state(blob, Photo::VARIANTS[name])
      when :missing then missing << name
      when :stale then stale << name
      end
    end

    problems = []
    problems << "missing #{missing.join(', ')}" if missing.any?
    problems << "file gone for #{stale.join(', ')}" if stale.any?
    problems
  end

  def gallery_photos(gallery)
    Photo.joins(:section)
         .where(sections: { gallery_id: gallery.id })
         .includes(:section, image_attachment: { blob: { variant_records: { image_attachment: :blob } } })
  end

  def photo_ids(gallery)
    Photo.joins(:section)
         .where(sections: { gallery_id: gallery.id })
         .order("sections.position ASC, photos.position ASC, photos.id ASC")
         .pluck(:id)
  end

  def image_paths(dir)
    Dir.children(dir).sort.filter_map do |name|
      path = File.join(dir, name)

      # Dotfiles first: an AppleDouble sidecar is named ._DSC0001.jpg and would
      # otherwise pass the extension check and fail at decode.
      if name.start_with?(".")
        say "  WARNING: skipping #{name} (dotfile)."
        next
      end
      if File.directory?(path)
        say "  WARNING: skipping directory #{name}; ingest does not recurse."
        next
      end
      unless CONTENT_TYPES.key?(File.extname(name).downcase)
        say "  WARNING: skipping #{name}; not an image type this task handles."
        next
      end

      path
    end
  end

  def worker_count
    # KTD15 says pick one level of parallelism, not both. This picks libvips:
    # VIPS_CONCURRENCY is left alone so each resize threads across the cores,
    # and the Ruby pool stays at 2. Measured per photo on 6000x4000 sources,
    # 10 cores: 1 worker 14.6s, 2 workers 12.3s, 4 workers 13.7s, and
    # 4 workers with VIPS_CONCURRENCY=1 13.9s. Past two workers the pool is
    # fighting libvips for the same cores and fighting itself for SQLite's
    # single writer.
    requested = ENV.fetch("PHOTOS_WORKERS", "2").to_i
    requested = 2 if requested < 1
    pool = ActiveRecord::Base.connection_pool.size
    if requested >= pool
      say "  NOTE: PHOTOS_WORKERS=#{requested} but the database pool holds #{pool}; using #{pool - 1}."
      requested = [ pool - 1, 1 ].max
    end
    requested
  end

  def without_active_storage_jobs
    install_enqueue_guard
    previous = Thread.current[SUPPRESSION_KEY]
    Thread.current[SUPPRESSION_KEY] = true
    yield
  ensure
    Thread.current[SUPPRESSION_KEY] = previous
  end

  def install_enqueue_guard
    @enqueue_guard_installed ||= begin
      SUPPRESSED_JOBS.each do |name|
        name.constantize.before_enqueue { throw :abort if Thread.current[PhotoTasks::SUPPRESSION_KEY] }
      end
      true
    end
  end

  def find_gallery!(slug)
    slug = slug.to_s.strip
    die("This task needs a gallery slug, e.g. photos:ingest[2025,day-1,/path/to/photos]") if slug.empty?

    Gallery.find_by(slug: slug) ||
      die("No gallery has the slug #{slug.inspect}. Known galleries: #{known(Gallery.order(:slug).pluck(:slug))}")
  end

  def find_section!(gallery, slug)
    slug = slug.to_s.strip
    die("This task needs a section slug, e.g. photos:ingest[#{gallery.slug},day-1,/path/to/photos]") if slug.empty?

    gallery.sections.find_by(slug: slug) ||
      die("Gallery #{gallery.slug.inspect} has no section #{slug.inspect}. " \
          "Its sections: #{known(gallery.sections.order(:position).pluck(:slug))}")
  end

  def known(slugs)
    slugs.any? ? slugs.join(", ") : "(none yet -- create one in the admin first)"
  end

  def say(message)
    $stdout.puts(message)
    $stdout.flush
  end

  def die(message)
    $stderr.puts(message)
    exit 1
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def duration(seconds)
    seconds = seconds.round
    return "#{seconds}s" if seconds < 60
    return "#{seconds / 60}m#{format('%02ds', seconds % 60)}" if seconds < 3600

    "#{seconds / 3600}h#{format('%02dm', (seconds % 3600) / 60)}"
  end

  # --- GPS ------------------------------------------------------------------

  # KTD11: the download button hands out the photographer's file verbatim, so a
  # GPS block in an original is attendee location data published to the web.
  # Ingest does not strip -- stripping mutates someone's files and belongs in
  # the runbook -- it refuses.
  module Gps
    module_function

    def scanner
      requested = ENV["PHOTOS_GPS_SCANNER"].to_s.strip
      case requested
      when "" then exiftool? ? :exiftool : PhotoTasks.die(no_exiftool_message)
      when "exiftool" then exiftool? ? :exiftool : PhotoTasks.die(no_exiftool_message)
      when "vips" then :vips
      else PhotoTasks.die("PHOTOS_GPS_SCANNER must be \"exiftool\" or \"vips\", got #{requested.inspect}.")
      end
    end

    def exiftool?
      system("exiftool", "-ver", out: File::NULL, err: File::NULL) ? true : false
    end

    def tagged(paths, scanner)
      scanner == :exiftool ? exiftool_tagged(paths) : vips_tagged(paths)
    end

    def exiftool_tagged(paths)
      found = []
      paths.each_slice(200) do |slice|
        # exiftool exits non-zero when no file matches -if, which is the good
        # case here, so the status is not a usable signal -- read the output.
        out, _status = Open3.capture2(
          "exiftool", "-m", "-q", "-q", "-if", "$gpslatitude or $gpslongitude",
          "-p", "$directory/$filename", *slice
        )
        found.concat(out.split("\n").map(&:strip).reject(&:empty?))
      end
      found
    end

    # libvips exposes the EXIF GPS IFD as exif-ifd3-* fields. Header-only read,
    # no pixels decoded. It covers the formats libvips parses EXIF for;
    # exiftool remains the authority, which is why it is the default.
    def vips_tagged(paths)
      require "vips"
      paths.select do |path|
        Vips::Image.new_from_file(path.to_s, access: :sequential)
             .get_fields.any? { |field| field.start_with?("exif-ifd3-GPS") }
      rescue Vips::Error
        false
      end
    end

    def no_exiftool_message
      <<~MESSAGE
        exiftool is not installed, so photos:ingest cannot confirm these originals carry no GPS data.

        Refusing to import. The download button hands out the original file verbatim, so an
        unchecked import publishes wherever each photo was taken (KTD11).

        Install it, then strip the sources:

          brew install exiftool
          exiftool -gps:all= -overwrite_original_in_place -r <directory>

        If the sources were stripped elsewhere and exiftool is genuinely unavailable here, run
        again with the libvips fallback scanner. It reads the same EXIF GPS block and still
        refuses any file carrying one:

          PHOTOS_GPS_SCANNER=vips bin/rails "photos:ingest[...]"
      MESSAGE
    end
  end

  def assert_gps_free!(paths, dir)
    scanner = Gps.scanner
    say "Checking #{paths.size} file(s) for GPS data with #{scanner}."
    tagged = Gps.tagged(paths, scanner)
    return if tagged.empty?

    listed = tagged.first(10).map { |path| "  #{path}" }
    listed << "  ... and #{tagged.size - 10} more" if tagged.size > 10
    die(<<~MESSAGE)
      #{tagged.size} file(s) still carry GPS data:
      #{listed.join("\n")}

      Nothing was imported. Strip them first (KTD11):

        exiftool -gps:all= -overwrite_original_in_place -r #{dir}
    MESSAGE
  end
end

namespace :photos do
  desc "Ingest a directory of images into one section: photos:ingest[gallery_slug,section_slug,directory]"
  task :ingest, %i[gallery_slug section_slug directory] => :environment do |_task, args|
    PhotoTasks.ingest(args[:gallery_slug], args[:section_slug], args[:directory])
  end

  desc "Bake every declared variant for every photo in a gallery: photos:preprocess[gallery_slug]"
  task :preprocess, %i[gallery_slug] => :environment do |_task, args|
    PhotoTasks.preprocess(args[:gallery_slug])
  end

  desc "Report photos missing any derivative, without generating one: photos:verify[gallery_slug]"
  task :verify, %i[gallery_slug] => :environment do |_task, args|
    PhotoTasks.verify(args[:gallery_slug])
  end
end
