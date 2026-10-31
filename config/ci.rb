# Run using bin/ci, or bin/ci-remote <lane> to run it in a container on the CI host.

CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Setup: Test database", "env RAILS_ENV=test bin/rails db:prepare"
  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
