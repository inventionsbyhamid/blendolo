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
- `AUTH_PROVIDER`: `google` (the default). `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`: a Google Cloud OAuth client of type Web application, with the redirect URI `https://<your host>/auth/google_oauth2/callback` and only the basic scopes (email, profile), which need no Google review. Publish the consent screen so anyone can sign in. Only the web app needs them; the worker boots without.
- `DODO_ENVIRONMENT`, `DODO_API_KEY`, `DODO_WEBHOOK_SECRET`, `DODO_PRODUCT_LOOK_PACK`, `DODO_PRODUCT_CLINIC`: payments through [Dodo Payments](https://dodopayments.com), the merchant of record. Put a test mode API key from the app's own Dodo business in an env file and run `bundle exec ruby script/billing/dodo_setup.rb <env file> --webhook-url https://<your host>/webhooks/dodo`: it checks the business, creates the two products and the webhook endpoint, and writes the other values into that file. Prices and credits live in `config/blendolo/plans.yml`. Optional: without them, buying says payments aren't working. A refund or a chargeback takes back what is left of that payment's credits by itself. Payments that matched no account (a static payment link, another customer) are stored and listed by `bin/rails billing:unmatched`: look at each in the Dodo dashboard.

Production stops at boot and names the variable when a required one is blank (`lib/required_env.rb`). After changing a variable, redeploy or restart both apps.

## How a request gets in

TLS ends at the platform's proxy, which forwards plain HTTP to port 80. Rails runs with `assume_ssl` and `force_ssl` (secure cookies, HSTS), answers only for its own host name (`config.hosts` in `config/environments/production.rb`), and lets `/up` answer any host so container health checks work.

## Deploys

A push to `main` builds and deploys the web app. Whether the worker follows on its own depends on the host: where it doesn't (for example when only the web app watches the repository), deploy the worker yourself once the web build is done, so both run the same commit. The web app migrates on start; a worker that starts before a release's migrations have run restarts until they have.

**Rolling back:** redeploy the previous commit (in Coolify: the app's Deployments tab, or set the commit to deploy and press Deploy) for both apps. Migrations are not reversed automatically, so a release that changes the schema needs a database backup restored too.

## After every deploy: checks

1. `curl -sI https://<your domain>/up` answers `200`, and `http://` redirects to `https://`.
2. The home page renders, and the browser console shows no Content Security Policy errors.
3. Upload a test photo, see the object appear in the R2 bucket, then delete it.
4. The worker's logs show Solid Queue started and no errors.
5. The database's backup list shows a recent successful run.

## Backups

The database is dumped every hour (`blendolo_production` only) and the last 12 dumps are kept on the server. They are copied to S3-compatible storage only when the backup schedule has a storage set up for it. The cache, queue and cable databases are not backed up: `db:prepare` rebuilds them.

## Taking it down

Take a last backup, then delete the web app, the worker and the database (with its volume). Outside the server: the DNS record, the R2 bucket and its token.
