# syntax=docker/dockerfile:1
# check=error=true

# Production image for friendlyfolio. Production itself runs on Hatchbox, not
# from this image; this is for running the real production build anywhere
# else -- locally through compose.yaml, or on any container host.
#
#   docker build -t friendlyfolio .
#   docker compose up            # see compose.yaml for the required env
#
# libvips comes with the AV1 encoder plugin (libheif-plugin-aomenc): without
# it every AVIF variant fails with "heifsave: Unsupported compression", and
# half of each photo's derivatives are AVIF.

ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 sqlite3 \
      libvips42 libheif-plugin-aomenc libheif-plugin-dav1d && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"


# Gems and assets are built here and copied out, so the compilers stay behind.
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Tailwind and Propshaft need no secrets to build.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

# storage/ holds the SQLite databases (storage/db) and, with the local
# service, the photos (storage/files). Mount a volume here or lose both.
VOLUME /rails/storage

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
