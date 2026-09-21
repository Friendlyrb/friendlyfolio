# frozen_string_literal: true

# Move existing Active Storage objects from the box's disk to Cloudflare R2.
#
#   bin/rails storage:to_r2            # copy, then repoint the rows
#   bin/rails storage:to_r2_check      # report only, changes nothing
#
# Restartable: an object already in the bucket is skipped, so a run that dies
# halfway costs nothing but the HEAD requests to find its place again.
#
# The service_name column is the reason this is a task and not an rsync. Every
# blob records which service holds it, so flipping the default service in
# production.rb leaves 19,160 rows still saying "local" and Rails still reading
# from disk. The bytes and the rows have to move together -- the same split that
# makes the photos:* tasks copy storage/db alongside storage/files.
#
# Local files are left in place on purpose. They are the only other copy of
# 17 GB that nothing else backs up.

namespace :storage do
  desc "Copy Active Storage objects from disk to R2 and repoint the blob rows"
  task to_r2: :environment do
    StorageTasks.migrate(dry_run: false)
  end

  desc "Report what storage:to_r2 would copy, without copying anything"
  task to_r2_check: :environment do
    StorageTasks.migrate(dry_run: true)
  end
end

module StorageTasks
  module_function

  def migrate(dry_run:)
    source = ActiveStorage::Blob.services.fetch(:local)
    target = ActiveStorage::Blob.services.fetch(:r2)

    pending = ActiveStorage::Blob.where.not(service_name: "r2")
    total = pending.count
    bytes = pending.sum(:byte_size)
    say "#{total} blob(s) to move, #{(bytes / 1024.0**3).round(2)} GB, into #{target.bucket.name}."

    if dry_run
      say "Dry run: nothing uploaded, nothing repointed."
      return
    end
    return say("Nothing to do.") if total.zero?

    queue = Queue.new
    pending.pluck(:id).each { |id| queue << id }
    workers = Integer(ENV.fetch("R2_WORKERS", "8"))
    workers.times { queue << :stop }

    mutex = Mutex.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    done = 0
    copied = 0
    already = 0
    failures = []

    Array.new(workers) {
      Thread.new do
        loop do
          id = queue.pop
          break if id == :stop

          begin
            result = ActiveRecord::Base.connection_pool.with_connection { move(id, source, target) }
            mutex.synchronize do
              done += 1
              result == :copied ? copied += 1 : already += 1
              if (done % 250).zero? || done == total
                elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
                eta = (elapsed / done) * (total - done)
                say "  [#{done}/#{total}] #{copied} copied, #{already} already there, eta #{(eta / 60).round}m"
              end
            end
          rescue StandardError => e
            mutex.synchronize do
              done += 1
              failures << "blob ##{id}: #{e.class}: #{e.message}"
              say "  [#{done}/#{total}] blob ##{id} FAILED: #{e.class}: #{e.message}"
            end
          end
        end
      end
    }.each(&:join)

    say "Copied #{copied}, skipped #{already} already present, #{failures.size} failed."
    if failures.any?
      failures.first(20).each { |f| warn "  #{f}" }
      abort "#{failures.size} blob(s) failed. Re-run; it resumes."
    end
    say "Done. #{ActiveStorage::Blob.where(service_name: 'r2').count} blob(s) now served from R2."
  end

  # Upload before repointing, never the other way round: a row that says "r2"
  # before the object is there is a 404 on a live page.
  def move(id, source, target)
    blob = ActiveStorage::Blob.find(id)
    return :already if blob.service_name == "r2"

    if target.exist?(blob.key)
      state = :already
    else
      source.open(blob.key, checksum: blob.checksum) do |file|
        target.upload(blob.key, file, checksum: blob.checksum,
                      content_type: blob.content_type, filename: blob.filename)
      end
      state = :copied
    end

    blob.update_column(:service_name, "r2")
    state
  end

  def say(message)
    $stdout.puts(message)
    $stdout.flush
  end
end
