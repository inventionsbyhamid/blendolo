# Replays recorded results with no network at all: development, tests, and demos without an API key.
# Stateless (everything it needs travels in the job's external_id), so the web and job processes agree.
class Appearance::FakeProvider < Appearance::Provider
  RESULTS = Rails.root.join("test/fixtures/files/youcam/makeup")
  FULL_LOOK = "m01_full_look.png"
  EASY_LOOK = "m02_easy_look.png"
  TRANSFER = "m03_mu_transfer.jpg"
  COSTS = { makeup: 1.0, transfer: 2.0 }.freeze
  PATTERNS = {
    blush: %w[Oblique1], eye_shadow: %w[1color6], eye_liner: %w[OpenWings2 Smoke4], eyelashes: %w[Natural2],
    eyebrows: %w[SoftArch3], lip_color: %w[original]
  }.freeze

  # ready_after: seconds a task stays running. fail_with: a reason every task fails with.
  def initialize(balance: 1000.0, ready_after: 0, fail_with: nil)
    @balance = balance
    @ready_after = ready_after
    @fail_with = fail_with
  end

  def start(operation, inputs)
    validate!(operation, inputs)
    result = operation == :transfer ? TRANSFER : look_for(inputs[:effects])
    Appearance::Job.new(operation:, external_id: "fake-#{SecureRandom.hex(6)}-#{result}", started_at: Time.current)
  end

  def fetch(job)
    if @fail_with
      Appearance::Outcome.new(state: :failed, reason: @fail_with)
    elsif Time.current - job.started_at < @ready_after
      Appearance::Outcome.new(state: :running)
    else
      Appearance::Outcome.new(state: :done, image_url: "fake://#{job.external_id.split('-', 3).last}",
        units: COSTS.fetch(job.operation))
    end
  end

  def download(outcome)
    name = File.basename(outcome.image_url.delete_prefix("fake://"))
    Appearance::Image.from_bytes(RESULTS.join(name).binread)
  end

  def balance = @balance

  def feature_cost(operation) = COSTS.fetch(operation)

  def patterns(category)
    PATTERNS.fetch(category.to_sym, []).map { |name| { name:, colours: 1, tags: [] } }
  end

  private
    # The recorded full look has a winged liner; the easy look swapped it for a smudged one.
    def look_for(effects)
      winged = effects.any? { |effect| effect.with_indifferent_access.values_at(:category, :pattern) in [ "eye_liner", /Wing/ ] }
      winged ? FULL_LOOK : EASY_LOOK
    end
end
