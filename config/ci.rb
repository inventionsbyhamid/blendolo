# Run using bin/ci, or bin/ci-remote <lane> to run it in a container on the CI host.

CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  # Advisory: both read advisories over the network, and a newly published one shouldn't stop every branch at once.
  # They print what they find and never fail the run, so read their output.
  step "Security: Gem audit (advisory)", "bin/bundler-audit || echo 'Gem audit found something or could not run: read the lines above.'"
  step "Security: Importmap audit (advisory)", "bin/importmap audit || echo 'Importmap audit found something or could not run: read the lines above.'"

  step "Setup: Test database", "env RAILS_ENV=test bin/rails db:prepare"
  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
