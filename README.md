# Blendolo

**The same red lip. Two mirrors. One of them takes eleven tries.**

Blendolo is makeup try-on for people whose hands shake or are stiff: Parkinson's, essential tremor, arthritis, MS, a stroke. It scores each look for your hands, swaps the hard steps for easier ones, and shows the classic and the easy version side by side on your own face before you buy anything.

- Live: https://blendolo.dijmo.com
- Try it with an example person (no photo, no account): https://blendolo.dijmo.com/examples
- For brands and shops: https://blendolo.dijmo.com/brands

## Why

- More than one in four of 2,864 people with essential tremor say tremor affects putting on makeup ([Gupta et al. 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8710410)).
- 5.33 million women live with Parkinson's, 45% of everyone with it ([GBD 2021, via Frontiers in Aging Neuroscience 2025](https://www.frontiersin.org/journals/aging-neuroscience/articles/10.3389/fnagi.2024.1498756/full)).
- 194 million people have osteoarthritis in their hands, women about twice as often as men ([Wei et al. 2025](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12350485/)).

Today's help is tip sheets and single tools for single steps. Virtual try-on shows a look on your face but never asks whether your hands can do it. Blendolo answers that question: can I do this look, and what is the easy version of it on me?

## What it does

1. **Five questions about your hands**: tremor, pinch or grip pain, one hand, arms that tire, close-up reading. They set your hand profile and how big the app's buttons are.
2. **A photo, hands free**: prop the phone up; the browser waits for one face, open eyes and a still second, then takes the photo with spoken help.
3. **Eight looks, scored for your hands**: each look is as easy as its hardest required step (Easy, Some care, Tricky or Hard), and each tile shows before and after, like "Hard → Some care".
4. **Classic and easy, side by side on your face**: hard steps are swapped for easier ones picked for your hands (winged liquid liner becomes shadow liner or a smudged pencil, liquid matte lipstick becomes a tinted balm dabbed on with a finger, brow pencil becomes tinted brow gel), and both versions are rendered on your photo in about 25 seconds; the page updates by itself. Each swap says why it's easier. Mascara has no easy version, and the app says so.
5. **Your signature look** ("Bring back your signature look" on the kit home or the looks list): an old photo of you wearing a look you loved is put on today's face, then rebuilt from easy steps in the same colours.
6. **Step cards, read aloud**: one step per screen, detailed steps first while hands are fresh, tidying up last; a large print view.
7. **A shopping list with ease tags**: what to look for and what to avoid for your hands ("Opens with one hand", "No pinch grip", "Pump", "Chunky, easy to hold").
8. **Ease tags for shops**: `GET /api/ease_tags?product_format=stick&closure=pull_cap&grip=chunky&step=tinted_balm` answers a product's tags and its ease for six kinds of hands. Free, no key, up to 60 requests a minute.
9. **Share with a helper or an occupational therapist**: a private link with a QR code that expires after 30 days and can be switched off. Example people have a read only demo share, "See what a helper sees".
10. **Three example people** (Rosa, June, Amara) with stored results.

The app follows its own advice: targets are 64 to 104 px depending on "My hands today", main buttons at least 88 px; a tap counts when you lift your finger and a quick second tap is ignored; no dragging, swiping, pinching, double taps or long presses; every control has visible words for Voice Control and Voice Access; one decision per screen; no time limits.

## How it uses the YouCam API

Blendolo uses two YouCam APIs from Perfect Corp, called only from the server.

| Endpoint | What it does here | Units |
|---|---|---|
| `POST /s2s/v2.0/task/makeup-vto` | The classic look and the easy version on your photo; the easy version of a signature look; "Softer" and "Bolder" | 1 per render, any number of effects in one call |
| `POST /s2s/v2.0/task/mu-transfer` | Puts the look from an old photo on today's photo | 2 |
| `POST /s2s/v2.0/file`, `GET /s2s/v2.0/credit/feature-cost`, `GET /s2s/v1.0/client/credit` | Photo upload, the live price list and the balance, for the unit guard | 0 |

Every swap is a parameter change in the Makeup VTO request: a winged liner pattern becomes a smudged one, a matte lip becomes sheer with more transparency, drawn brows become tinted brows, lip liner is left out. The full table and the request shape are in [docs/effects-vocabulary.md](docs/effects-vocabulary.md).

Around the API:

- **Cache**: one render per photo, operation and effect list, under a row lock, so a repeated view or a double tap never calls twice. Results are copied to our storage straight away.
- **Unit guard**: example people never call the API; each kit can make 10 Makeup VTO renders and 2 transfers; the app stops at `YOUCAM_DAILY_UNIT_CAP` units a day (40 on the live site) and never goes below `YOUCAM_UNIT_FLOOR` (150). Failures that may have been charged still count.
- **Throttle**: at least 1.4 s between any two requests across the web app and the worker, under YouCam's 250 requests per 5 minutes.
- **Webhook and polling**: a webhook at `POST /webhooks/youcam` triggers a poll; polling runs anyway and gives up after 3 minutes with a clear message.
- **Several keys**: `YOUCAM_API_KEYS` takes a comma separated list; a call uses the first key above the floor.

## How it is built

Rails 8.1, Hotwire, Tailwind, Postgres with Solid Queue, Cache and Cable, Active Storage (Cloudflare R2 in production), MediaPipe Face Landmarker in the browser for capture checks and colour sampling, and the Web Speech API for reading cards aloud.

| Where | What |
|---|---|
| `config/blendolo/steps.yml` | 40 makeup steps, classic and easy, each scored 0 to 3 for precision, closeness to the eye, grip, hands needed, time, forgiveness and opening, with their easier swaps, tips and product types |
| `config/blendolo/looks.yml`, `examples.yml`, `products.yml`, `caps.yml` | The 8 looks, the example people, the demo catalogue and the unit caps |
| `app/models/ease/` | The ease engine: hand profile weights, step and look scores, the swap planner, routine order |
| `app/models/looks/` | Turns steps into effects in our own vocabulary; snaps colours read from a photo to our shades |
| `app/models/appearance/` | The provider interface, the YouCam adapter and a fake provider that replays recorded responses |
| `app/models/unit_guard.rb`, `provider_throttle.rb`, `previews.rb`, `app/jobs/provider_*` | Caps, throttle, cache, start and poll jobs |
| `app/javascript/capture/` | The capture checks and colour sampling in the browser |

## Try it in 90 seconds

1. Open https://blendolo.dijmo.com/examples, choose **Rosa**, then "Open Rosa's kit".
2. **Looks** → **The red lip**: classic and easy side by side, what changes and why, the ease before and after.
3. **Make this my routine** → **Start with step 1** → "Read it to me".
4. **Shopping list**, then "Ease tags for brands and shops".
5. **Bring back your signature look**, then back on Rosa's kit, **See what a helper sees**.
6. In the **Menu**, set "My hands today" to "Very shaky or stiff" and watch every button grow.

## Honest limits

- Ease scores are our own rubric, built from published guidance (Parkinson's UK, the Parkinson's Foundation) and people's own words. They are not a clinical measure, and they have not been tested with people with tremor yet.
- Previews are visual simulations: renders are always clean, real lines wobble. That's why the easy steps are forgiving ones.
- Makeup VTO smooths skin a little by default and brightens the whole frame, so we compare render with render.
- Makeup Transfer moves a whole look at once; blush can land stronger on one cheek.
- Colours read from an old photo are approximate and snap to a small set of shades.
- Taking the photo hands free needs a recent browser with camera access; "Choose a photo" always works.
- Example people are AI generated. The shopping catalogue is made-up demo products.
- Blendolo is not a medical device and gives no medical advice.

## Privacy

No account and no trackers. A kit lives behind a private link and is deleted 30 days (or 7, your choice) after your last visit, or at once with "Delete everything". Photos go from your phone to our server and storage, then to YouCam to make the previews; YouCam deletes its copies within 30 days.

## Run it

Development and tests use the fake provider, so they need no keys and spend no units. See "Run it locally" and "Tests" below. The example people are seeded when `bin/setup` prepares a new database, and `bin/rails examples:rebuild` builds them again.

To use the real API, set `APPEARANCE_PROVIDER=youcam` and `YOUCAM_API_KEYS`, and optionally `YOUCAM_DAILY_UNIT_CAP`, `YOUCAM_UNIT_FLOOR` and `YOUCAM_WEBHOOK_SECRET` (point the webhook at `/webhooks/youcam`). [.env.example](.env.example) explains every variable.

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

At the last CI run there were 316 unit and integration tests and 42 system tests in headless Chrome, all passing.

`bin/ci-remote <lane>` runs the same `bin/ci` in Docker on another machine over ssh, so the full suite doesn't load your laptop. It copies the working tree, builds a CI image with Chromium (`script/ci/Dockerfile`), starts a throwaway Postgres 18 beside it and cleans up afterwards. Set `BLENDOLO_CI_HOST` to the ssh host, which needs Docker, rsync and flock. Lanes let several worktrees run at once:

```sh
BLENDOLO_CI_HOST=ci.example.com bin/ci-remote main
```

## Environment

Production reads its settings from environment variables and refuses to boot while a required one is missing. [`.env.example`](.env.example) lists and explains each one.

## Production image

The `Dockerfile` builds one image for both processes: the web server (Thruster in front of Puma, on port 80) and, with `BLENDOLO_PROCESS=jobs`, the Solid Queue worker. The web container prepares the databases when it starts. Health checks use `GET /up`, which answers on any host. [docs/deploy.md](docs/deploy.md) covers running it in production: settings, storage, deploys, checks and backups.

## License

[AGPL-3.0](LICENSE)
