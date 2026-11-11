# The Ruby 3.2 image of the lint and the tests (bin/lint, bin/test, CI: TEST_RUBY=3.2),
# pinned here so that Dependabot (docker, /test) updates its digest. The
# scripts read the FROM line; this file is not built.
FROM ruby:3.2@sha256:d3bcbd845d26ae1efafcc987f641aa9ac796267b9b857e0f196a2b05070c8330
