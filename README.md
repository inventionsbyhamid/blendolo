# Blendolo

Blendolo: makeup made easier for hands that shake or are stiff.

## Run it locally

You need Ruby 3.4.12 (see `.ruby-version`), PostgreSQL, and Google Chrome for the system tests.

```sh
bin/setup   # installs gems, prepares the database and starts the app
bin/dev     # starts the app again later
```

The app runs at http://localhost:3107. Development and tests need no environment variables.

## Tests

```sh
bin/rails test          # unit and integration tests
bin/rails test:system   # browser tests in headless Chrome
bin/ci                  # everything CI checks
```

`bin/ci` runs RuboCop (Rails omakase style), Brakeman, the tests, the system tests and the seeds. The steps live in `config/ci.rb`.

`bin/ci-remote <lane>` runs the same `bin/ci` in Docker on another machine over ssh, so the full suite doesn't load your laptop. It copies the working tree, builds a CI image with Chromium (`script/ci/Dockerfile`), starts a throwaway Postgres 18 beside it and cleans up afterwards. Set `BLENDOLO_CI_HOST` to the ssh host, which needs Docker, rsync and flock. Lanes let several worktrees run at once:

```sh
BLENDOLO_CI_HOST=ci.example.com bin/ci-remote main
```

## Environment

Production reads its settings from environment variables and refuses to boot while a required one is missing. [`.env.example`](.env.example) lists and explains each one.

## Production image

The `Dockerfile` builds one image for both processes: the web server (Thruster in front of Puma, on port 80) and, with `BLENDOLO_PROCESS=jobs`, the Solid Queue worker. The web container prepares the databases when it starts. Health checks use `GET /up`, which answers on any host.

## License

[AGPL-3.0](LICENSE)
