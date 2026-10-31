# The live provider: YouCam makeup VTO (:makeup) and makeup transfer (:transfer).
#
# Keys: YOUCAM_API_KEYS is a comma-separated list; each call uses the first key whose balance is at or above
# YOUCAM_UNIT_FLOOR. Cache keys use a fingerprint of the key, never the key.
# Uploads: each photo goes up once as a JPEG derivative (Derivative), and its file id is reused for a day.
# Nothing YouCam-shaped leaves this class: callers get Appearance::Job, Outcome, Image and Error.
class Appearance::Youcam::Provider < Appearance::Provider
  Client = Appearance::Youcam::Client
  Mapper = Appearance::Youcam::Mapper

  TASKS = { makeup: "makeup-vto", transfer: "mu-transfer" }.freeze
  KNOWN_COSTS = { makeup: 1.0, transfer: 2.0 }.freeze # the live price list on 2026-10-31
  PATTERNS_URL = "https://plugins-media.makeupar.com/wcm-saas/".freeze
  PATTERN_FILES = {
    "blush" => "patterns/blush.json", "bronzer" => "patterns/bronzer.json", "contour" => "patterns/contour.json",
    "highlighter" => "patterns/highlighter.json", "eyebrows" => "patterns/eyebrows.json",
    "eye_shadow" => "patterns/eyeshadow.json", "eye_liner" => "patterns/eyeliner.json",
    "eyelashes" => "patterns/eyelashes.json", "lip_liner" => "patterns/lipliner.json",
    "lip_color" => "shapes/lipshape.json"
  }.freeze
  BALANCE_TTL = 1.minute
  CATALOG_TTL = 12.hours
  FILE_TTL = 1.day
  # Poll answers that only mean "ask again later".
  TRANSIENT_STATUSES = [ 0, 429, 500, 502, 503, 504 ].freeze

  def self.from_env(env = ENV, before_request: nil)
    keys = env["YOUCAM_API_KEYS"].to_s.split(",").map(&:strip).compact_blank
    new(keys:, floor: env.fetch("YOUCAM_UNIT_FLOOR", 150).to_f, client: Client.new(before_request:))
  end

  def initialize(keys:, floor:, client: Client.new, cache: Rails.cache)
    raise ArgumentError, "YOUCAM_API_KEYS is empty" if keys.empty?

    @keys = keys
    @floor = floor
    @client = client
    @cache = cache
  end

  def start(operation, inputs)
    validate!(operation, inputs)
    effects = mapped_effects(inputs[:effects]) if operation == :makeup
    key = active_key

    body = case operation
    when :makeup then { src_file_id: upload(key, inputs[:photo]).first, version: "1.0", effects: }
    when :transfer then upload(key, inputs[:photo], inputs[:reference]).then { |src, ref| { src_file_id: src, ref_file_id: ref } }
    end
    task_id = translate { @client.post("/s2s/v2.0/task/#{TASKS.fetch(operation)}", body, key:) }.dig("data", "task_id")
    @cache.write(task_key(task_id), fingerprint(key), expires_in: 1.day)

    Appearance::Job.new(operation:, external_id: task_id, started_at: Time.current)
  end

  def fetch(job)
    path = "/s2s/v2.0/task/#{TASKS.fetch(job.operation)}/#{job.external_id}"
    data = with_task_key(job.external_id) { |key| @client.get(path, key:) }.fetch("data", {})

    case data["task_status"]
    when "success" then Appearance::Outcome.new(state: :done, image_url: data.dig("results", "url"))
    when "error" then Appearance::Outcome.new(state: :failed, reason: Mapper.reason(data["error"]), about: Mapper.about(data["error"]))
    else Appearance::Outcome.new(state: :running)
    end
  rescue Client::HttpError => error
    if error.status.in?(TRANSIENT_STATUSES) && error.code != "TaskTimeout"
      Appearance::Outcome.new(state: :running)
    else
      Appearance::Outcome.new(state: :failed, reason: reason_for(error))
    end
  end

  def download(outcome)
    Appearance::Image.from_bytes(translate { @client.download(outcome.image_url) })
  end

  # The balance of the key in use, or the best one when every key is below the floor.
  def balance
    balances = @keys.filter_map { |key| balance_for(key) }
    raise Appearance::Error.new(:provider_error, message: "no balance for any key") if balances.empty?

    balances.find { |units| units >= @floor } || balances.max
  end

  def feature_cost(operation)
    @cache.fetch("youcam/feature-cost", expires_in: CATALOG_TTL) { price_list }.fetch(operation.to_s) do
      KNOWN_COSTS.fetch(operation)
    end
  rescue Appearance::Error
    KNOWN_COSTS.fetch(operation)
  end

  def patterns(category)
    file = PATTERN_FILES[category.to_s] or return []

    @cache.fetch("youcam/patterns/#{category}", expires_in: CATALOG_TTL) do
      JSON.parse(translate { @client.download(PATTERNS_URL + file) }).map do |pattern|
        { name: pattern["label"], colours: pattern["colorNum"] || 1, tags: Array(pattern["tags"]).pluck("name") }
      end
    end
  end

  private
    def active_key
      balances = @keys.index_with { |key| balance_for(key) }
      raise Appearance::Error.new(:provider_error, message: "no balance for any key") if balances.values.none?

      balances.find { |_key, units| units.to_f >= @floor }&.first ||
        raise(Appearance::Error.new(:out_of_units, message: "every key is below the unit floor"))
    end

    # Units on a key, or nil when the provider won't say (that key is skipped).
    def balance_for(key)
      @cache.fetch("youcam/balance/#{fingerprint(key)}", expires_in: BALANCE_TTL, skip_nil: true) do
        now = Time.current.to_i * 1000
        Array(@client.get("/s2s/v1.0/client/credit", key:)["results"])
          .select { |credit| credit["expiry"].nil? || credit["expiry"] > now }
          .sum { |credit| (credit["amount_dec"] || credit["amount"]).to_f }
      rescue Client::HttpError => error
        Rails.logger.warn("YouCam balance unavailable for a key: #{error.message}")
        nil
      end
    end

    # Registers every photo not uploaded yet in one call, then PUTs each one exactly as told.
    def upload(key, *images)
      jpegs = images.map { |image| Appearance::Youcam::Derivative.jpeg(image) }
      ids = jpegs.map { |jpeg| @cache.read(file_key(key, jpeg)) }
      missing = ids.each_index.select { |index| ids[index].nil? }
      return ids if missing.empty?

      files = missing.map { |index| { content_type: "image/jpeg", file_name: "#{SecureRandom.hex(8)}.jpg", file_size: jpegs[index].bytesize } }
      registered = translate { @client.post("/s2s/v2.0/file", { files: }, key:, safe: true) }.dig("data", "files")

      missing.each_with_index do |index, position|
        file = registered.find { |entry| entry["file_name"] == files[position][:file_name] } || registered[position]
        put = file["requests"].first
        translate { @client.put(put["url"], jpegs[index], headers: put["headers"]) }
        ids[index] = file["file_id"]
        @cache.write(file_key(key, jpegs[index]), ids[index], expires_in: FILE_TTL)
      end
      ids
    end

    # A task can only be read with the key that started it: try that one first, then the others.
    def with_task_key(task_id)
      started_with = @cache.read(task_key(task_id))
      keys = @keys.sort_by { |key| fingerprint(key) == started_with ? 0 : 1 }
      keys.each_with_index do |key, index|
        return yield(key)
      rescue Client::HttpError => error
        raise unless error.code == "InvalidTaskId" && index < keys.size - 1
      end
    end

    def price_list
      key = active_key
      costs = {}
      token = nil
      loop do
        query = { page_size: 20, starting_token: token }.compact.to_query
        result = translate { @client.get("/s2s/v2.0/credit/feature-cost?#{query}", key:) }["result"] || {}
        Array(result["skus"]).each do |sku|
          TASKS.each do |operation, task|
            costs[operation.to_s] ||= sku["amount"].to_f if sku["run_task_url"].to_s.end_with?("/task/#{task}")
          end
        end
        token = result["next_token"]
        break if token.blank? || costs.size == TASKS.size
      end
      costs
    end

    def mapped_effects(effects)
      Mapper.effects(effects)
    rescue ArgumentError => error
      raise Appearance::Error.new(:provider_error, message: "effects can't be sent: #{error.message}")
    end

    def translate
      yield
    rescue Client::HttpError => error
      raise Appearance::Error.new(reason_for(error), message: error.message)
    end

    def reason_for(error)
      error.status == 429 ? :rate_limited : Mapper.reason(error.code)
    end

    def fingerprint(key) = Digest::SHA256.hexdigest(key).first(16)
    def file_key(key, jpeg) = "youcam/file/#{fingerprint(key)}/#{Digest::SHA256.hexdigest(jpeg)}"
    def task_key(task_id) = "youcam/task-key/#{task_id}"
end
