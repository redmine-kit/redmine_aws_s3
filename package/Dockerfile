# syntax=docker/dockerfile:1
# The plugin's run-time files as an image at /redmine_serverless_s3, published to
# ghcr.io/redmine-kit/redmine_serverless_s3 (.github/workflows/package.yml). A Redmine image
# takes them with:
#   COPY --from=ghcr.io/redmine-kit/redmine_serverless_s3:<tag>@sha256:<digest> /redmine_serverless_s3 plugins/redmine_serverless_s3/
# .dockerignore chooses the files; those that do not exist yet are left out.
# Built from the repository root: docker build -f package/Dockerfile .
FROM scratch
LABEL org.opencontainers.image.source=https://github.com/redmine-kit/redmine_serverless_s3 \
  org.opencontainers.image.description="The Redmine plugin redmine_serverless_s3: run-time files" \
  org.opencontainers.image.licenses=GPL-2.0-or-later
COPY . /redmine_serverless_s3/
