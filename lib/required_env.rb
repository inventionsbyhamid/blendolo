# The environment variables production can't run without. config/initializers/required_env.rb checks them at boot,
# so a missing one stops the web, jobs and console processes straight away, by name, instead of failing later on the
# first upload or provider call. .env.example documents each one.
module RequiredEnv
  class Missing < StandardError; end
  class Invalid < StandardError; end

  # Each entry is a name, or a list of names any one of which will do.
  PRODUCTION = [
    %w[RAILS_MASTER_KEY SECRET_KEY_BASE],
    "DB_HOST",
    "BLENDOLO_DATABASE_PASSWORD",
    "R2_ACCOUNT_ID",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_BUCKET",
    "APPEARANCE_PROVIDER",
    "BLENDOLO_PROCESS"
  ].freeze

  # Variables that take one of a few words. A typo such as APPEARANCE_PROVIDER=YouCam would otherwise skip the YouCam
  # checks, or run neither process.
  ALLOWED = { "APPEARANCE_PROVIDER" => %w[youcam fake], "BLENDOLO_PROCESS" => %w[web jobs] }.freeze

  # Needed only with the live provider (APPEARANCE_PROVIDER=youcam). YOUCAM_WEBHOOK_SECRET stays optional.
  YOUCAM = %w[YOUCAM_API_KEYS YOUCAM_DAILY_UNIT_CAP YOUCAM_UNIT_FLOOR].freeze

  module_function

  # The entries production checks, given the environment it boots with.
  def production(env = ENV)
    env["APPEARANCE_PROVIDER"].to_s.strip == "youcam" ? PRODUCTION + YOUCAM : PRODUCTION
  end

  # Raises Missing naming the first entry none of whose names has a value. It names variables, never values: the
  # message ends up in logs.
  def check!(names, env: ENV)
    blank = names.find { |entry| Array(entry).all? { |name| env[name].to_s.strip.empty? } }
    return if blank.nil?

    raise Missing, "Missing environment variable #{Array(blank).join(' or ')}. " \
                   "Set it (see .env.example), then start again."
  end

  # Raises Invalid naming the first set variable whose value isn't one of its allowed words (blank ones are check!'s
  # job). Like check!, it never repeats the value.
  def check_values!(env: ENV)
    name, allowed = ALLOWED.find { |key, words| env[key].present? && !env[key].strip.in?(words) }
    return if name.nil?

    raise Invalid, "#{name} must be #{allowed.join(' or ')}. Fix it (see .env.example), then start again."
  end
end
