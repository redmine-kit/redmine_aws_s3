# The Ruby 4.0 image of the lint and the tests (bin/lint, bin/test, CI: TEST_RUBY=4.0),
# pinned here so that Dependabot (docker, /test) updates its digest. The
# scripts read the FROM line; this file is not built.
FROM ruby:4.0@sha256:a69f361db050bb2c65ec66ef75411bfc4ce2e1d993ba1179fac4e4ba6ecfe91f
