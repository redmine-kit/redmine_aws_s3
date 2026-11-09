# syntax=docker/dockerfile:1
# Redmine 7.0.3 with this plugin, for the tests (bin/test). Built from the
# repository root: docker build -f test/Dockerfile .
FROM ruby:4.0@sha256:a69f361db050bb2c65ec66ef75411bfc4ce2e1d993ba1179fac4e4ba6ecfe91f
# Thumbnails (ImageMagick, Ghostscript), as in the Serverless image.
RUN apt-get update && apt-get install -y --no-install-recommends imagemagick ghostscript \
  && rm -rf /var/lib/apt/lists/*
ARG REDMINE_VERSION=7.0.3
ARG REDMINE_SHA256=0b6b24c033341a9d7ad52cfcfa7b1bc913c191c7a604f740d863f16249dd3c15
RUN curl -fsSLo /tmp/redmine.tar.gz "https://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz" \
  && echo "${REDMINE_SHA256}  /tmp/redmine.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/redmine.tar.gz -C / \
  && mv "/redmine-${REDMINE_VERSION}" /redmine \
  && rm /tmp/redmine.tar.gz
WORKDIR /redmine
COPY test/database.yml config/database.yml
# The plugin's Gemfile first, so that a change of the code does not install
# the gems again. Redmine's Gemfile loads plugins/*/Gemfile.
COPY Gemfile plugins/redmine_serverless_s3/Gemfile
RUN bundle config set --local without development
# Coverage in Cobertura for Codecov (test/test_helper.rb), for the tests only.
RUN printf "group :test do\n  gem 'simplecov-cobertura', require: false\nend\n" > Gemfile.local
# Redmine's and the plugin's gems are resolved at build time, without a lock,
# so the tests run with the newest versions the Gemfiles allow.
RUN bundle install --jobs 4
COPY . plugins/redmine_serverless_s3/
COPY test/core/additional_environment.rb config/additional_environment.rb
ENV RAILS_ENV=test
