# syntax=docker/dockerfile:1
# The base image of the Redmine Kit plugins' tests (bin/test, bin/test-gem): Ruby,
# Redmine 7.0.3 and its gems, and nothing of any plugin. The same file in every
# plugin's repository, so that one image serves them all: bin/test_image tags it
# with this file's hash and builds it only when no image has that tag (a new
# Redmine or a changed pin here). The plugins come at run time: bin/test_image
# mounts their files at /src/plugins/<plugin id>, and the entrypoint copies them
# into Redmine's plugins/ and installs the gems their Gemfiles add into
# /extra-gems, a named volume of the plugin (kept between runs).
# REDMINE_COMMIT=<sha> takes that commit of Redmine's repository instead of the
# release (Redmine's master branch: REDMINE_BRANCH=master bin/test).
FROM ruby:4.0@sha256:a69f361db050bb2c65ec66ef75411bfc4ce2e1d993ba1179fac4e4ba6ecfe91f
# Ghostscript for Redmine's tests that export PDF and PNG; ImageMagick for the
# thumbnails, as in the Serverless image (redmine_kit_aws_s3 only: this plugin's
# base image is its own).
RUN apt-get update && apt-get install -y --no-install-recommends ghostscript imagemagick && rm -rf /var/lib/apt/lists/*
ARG REDMINE_VERSION=7.0.3
ARG REDMINE_SHA256=0b6b24c033341a9d7ad52cfcfa7b1bc913c191c7a604f740d863f16249dd3c15
ARG REDMINE_COMMIT=
RUN if [ -n "$REDMINE_COMMIT" ]; then \
    curl -fsSLo /tmp/redmine.tar.gz "https://github.com/redmine/redmine/archive/${REDMINE_COMMIT}.tar.gz" \
    && mkdir /redmine && tar -xzf /tmp/redmine.tar.gz -C /redmine --strip-components=1; \
  else \
    # redmine.org can close the connection before the end: continue the download.
    for attempt in 1 2 3 4 5; do \
      curl -fsSL -C - -o /tmp/redmine.tar.gz "https://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz" && break; \
    done \
    && echo "${REDMINE_SHA256}  /tmp/redmine.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/redmine.tar.gz -C / && mv "/redmine-${REDMINE_VERSION}" /redmine; \
  fi \
  && rm /tmp/redmine.tar.gz
WORKDIR /redmine
# The tests' database (TEST_DATABASE_HOST, TEST_DATABASE: bin/test), as every
# plugin's test/database.yml has it.
RUN printf '%s\n' 'test:' '  adapter: postgresql' \
    "  host: <%= ENV.fetch('TEST_DATABASE_HOST', 'postgres') %>" \
    "  database: <%= ENV.fetch('TEST_DATABASE', 'redmine_test') %>" \
    '  username: postgres' '  encoding: unicode' > config/database.yml
# The plugin's coverage as Cobertura XML for Codecov (COVERAGE=1 bin/test).
# simplecov-cobertura 3.2.0 on Redmine 7.0.3, whose Gemfile holds simplecov at
# ~> 0.22.0 (4.0.0 needs simplecov 1); 4.0.0 on master (simplecov ~> 1.3.0).
RUN if [ -n "$REDMINE_COMMIT" ]; then cobertura=4.0.0; else cobertura=3.2.0; fi \
  && printf "gem 'simplecov-cobertura', '%s', group: :test\n" "$cobertura" > Gemfile.local \
  && bundle config set --local without development \
  && bundle install --jobs 4
# Redmine's gems stay in /usr/local/bundle (this image); the gems the plugins'
# Gemfiles add go to /extra-gems (the plugin's named volume, or the container's
# own folder without one), found through GEM_PATH.
ENV GEM_HOME=/extra-gems GEM_PATH=/extra-gems:/usr/local/bundle PATH=/extra-gems/bin:$PATH RAILS_ENV=test
# The entrypoint: the plugins mounted at /src/plugins copied into plugins/ (a
# copy, so that a test may move or change them, as bin/test-gem does; a folder
# without init.rb, an optional plugin that isn't there, is left out), then
# their gems installed when the bundle lacks them. The lock that install wrote
# is kept in /extra-gems per lock of this image, so that the next run resolves
# nothing and fetches nothing.
RUN printf '%s\n' '#!/bin/sh' 'set -e' \
    'for dir in /src/plugins/*; do' \
    '  [ -f "$dir/init.rb" ] || continue' \
    '  mkdir -p "plugins/${dir##*/}" && cp -a "$dir/." "plugins/${dir##*/}/"' \
    'done' \
    'lock="/extra-gems/locks/$(sha256sum Gemfile.lock | cut -c1-16).lock"' \
    'if [ -f "$lock" ]; then cp "$lock" Gemfile.lock; fi' \
    'if ! bundle check >/dev/null 2>&1; then' \
    '  bundle install --quiet --jobs 4' \
    '  mkdir -p /extra-gems/locks && cp Gemfile.lock "$lock"' \
    'fi' \
    'exec "$@"' > /usr/local/bin/kit-test-entrypoint \
  && chmod +x /usr/local/bin/kit-test-entrypoint
ENTRYPOINT ["/usr/local/bin/kit-test-entrypoint"]
