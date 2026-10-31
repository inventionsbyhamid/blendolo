# Deploying Blendolo

Blendolo runs as three containers built from this repo's `main` branch: a web app, a background worker and a Postgres database. We run them on a self-hosted [Coolify](https://coolify.io) server, but nothing below depends on Coolify: any platform that builds a Dockerfile, sets runtime environment variables and puts a TLS proxy in front will do.

## What runs

| Resource | What it is |
| --- | --- |
| web | This repo's `Dockerfile`: Thruster in front of Puma on port 80. Health check `GET /up`. On start it runs `bin/rails db:prepare`, which creates and migrates the databases. |
| worker | The same image with `BLENDOLO_PROCESS=jobs`, which starts Solid Queue (`bin/jobs`) instead of the web server. No port, no health check. |
| database | Postgres 18, reachable only from the two apps. It holds `blendolo_production` plus the cache, queue and cable databases, which `db:prepare` creates. |

Caps we use: web 2 CPUs and 2 GB, worker 1 CPU and 1 GB, database 1 CPU and 1 GB.

## Settings

Every variable in [`.env.example`](../.env.example) that production uses is set as a **runtime** variable on both apps, never as a build argument. The `Dockerfile` refuses to build when a secret is passed as a build argument (`# check=error=true`), and the build needs none: assets compile with a dummy key.

- `SECRET_KEY_BASE`: make one with `bin/rails secret` or `openssl rand -hex 64`. Both apps share it.
- `DB_HOST`: the database container's host name on the private network. `BLENDOLO_DATABASE_PASSWORD`: the password of the `blendolo` role.
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`: a private Cloudflare R2 bucket and an API token limited to Object Read and Write on that bucket alone. Uploaded photos and renders go there (`config/storage.yml`, service `r2`).
- `APPEARANCE_PROVIDER`: `fake` replays recorded responses and costs nothing; `youcam` calls the live API and then also needs `YOUCAM_API_KEYS`, `YOUCAM_DAILY_UNIT_CAP` and `YOUCAM_UNIT_FLOOR`.
- `BLENDOLO_PROCESS`: `web` on the web app, `jobs` on the worker.

Production stops at boot and names the variable when a required one is blank (`lib/required_env.rb`). After changing a variable, redeploy or restart both apps.

## How a request gets in

TLS ends at the platform's proxy, which forwards plain HTTP to port 80. Rails runs with `assume_ssl` and `force_ssl` (secure cookies, HSTS), answers only for its own host name (`config.hosts` in `config/environments/production.rb`), and lets `/up` answer any host so container health checks work.

## Deploys

A push to `main` builds and deploys both apps. The web app migrates on start; a worker that starts before a release's migrations have run restarts until they have.

**Rolling back:** redeploy the previous commit (in Coolify: the app's Deployments tab, or set the commit to deploy and press Deploy) for both apps. Migrations are not reversed automatically, so a release that changes the schema needs a database backup restored too.

## After every deploy: checks

1. `curl -sI https://<your domain>/up` answers `200`, and `http://` redirects to `https://`.
2. The home page renders, and the browser console shows no Content Security Policy errors.
3. Upload a test photo, see the object appear in the R2 bucket, then delete it.
4. The worker's logs show Solid Queue started and no errors.
5. The database's backup list shows a recent successful run.

## Backups

The database is dumped every hour (`blendolo_production` only) and the dumps are kept on the server and copied to S3-compatible storage. The cache, queue and cable databases are not backed up: `db:prepare` rebuilds them.

## Taking it down

Take a last backup, then delete the web app, the worker and the database (with its volume). Outside the server: the DNS record, the R2 bucket and its token.
