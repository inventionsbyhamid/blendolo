# Records Blendolo's voice lines (Voice.lines) with Fish Audio text to speech: one mp3 per line in public/voice,
# named by the line's key, and public/voice/manifest.json. A line that already has a file is skipped, so a rerun only
# records new or changed lines; delete a file (or name its key) to record it again. Files of lines no longer in the
# list are removed.
#
#   FISH_AUDIO_API_KEY=... FISH_VOICE_ID=... bin/rails runner script/voice/generate.rb [key prefix ...]
#
# With key prefixes, only those lines are recorded (again, if they have a file). The key and the voice come from the
# environment only. Durations come from ffprobe.
#
# The voice is calm, warm and clear, a little slower than a narrator: the listener is in the middle of a task. Fish
# S2 reads an emotion tag in square brackets at the start of a sentence, and the tags go only into the request: the
# app shows and stores the plain words.
require "net/http"
require "json"
require "open3"

module VoiceRecorder
  ENDPOINT = URI("https://api.fish.audio/v1/tts")
  MODEL = "s2.1-pro".freeze
  # Fish's price for this model, per million UTF-8 bytes of text sent (docs.fish.audio, October 2026).
  DOLLARS_PER_MILLION_BYTES = 15.0
  SETTINGS = { format: "mp3", sample_rate: 44_100, mp3_bitrate: 64, temperature: 0.6, top_p: 0.7, latency: "normal",
               language: "en", normalize: true, prosody: { speed: 0.75, volume: 0, normalize_loudness: true } }.freeze

  # Words said differently from how they're written.
  SPOKEN = { "1" => "One.", "2" => "Two.", "3" => "Three.", "4" => "Four.", "5" => "Five.", "6" => "Six.",
             "7" => "Seven.", "8" => "Eight.", "9" => "Nine.", "10" => "Ten." }.freeze
  SPELLINGS = { /\bBlendolo\b/ => "Blend-oh-loh" }.freeze

  module_function

  # The request's text: the line's words with one tag at the start of each part of a card (calm for what to do, warm
  # for why it's easier, encouraging for the tip) and one for a photo prompt (warm for "Got it", calm otherwise).
  def speech(text)
    return SPOKEN.fetch(text) if SPOKEN.key?(text)

    spoken = SPELLINGS.reduce(text) { |words, (pattern, spelling)| words.gsub(pattern, spelling) }
    spoken = spoken.sub(/ (?=Why this is easier: )/, " [warm] ").sub(/ (?=Tip: )/, " [encouraging] ")
    if spoken.start_with?("Got it")
      spoken.sub(/\AGot it\./, "[warm] Got it. [calm]").sub(/\AGot it\z/, "[warm] Got it.")
    else
      "[calm] #{spoken}"
    end
  end

  def record(text, destination)
    spoken = speech(text)
    body = SETTINGS.merge(text: spoken, reference_id: ENV.fetch("FISH_VOICE_ID")).to_json
    request = Net::HTTP::Post.new(ENDPOINT)
    request["Authorization"] = "Bearer #{ENV.fetch("FISH_AUDIO_API_KEY")}"
    request["Content-Type"] = "application/json"
    request["model"] = MODEL
    request.body = body

    attempts = 0
    begin
      attempts += 1
      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 15, read_timeout: 180) do |http|
        http.request(request)
      end
      # Only the status: the body or headers could echo a credential.
      raise "Fish TTS: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      raise "Fish TTS: #{response.body.bytesize} bytes is too short for audio" if response.body.bytesize < 1000
    rescue StandardError => error
      transient = error.message.match?(/HTTP (429|5\d\d)/) || error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
      raise unless transient && attempts < 3

      sleep 2 * attempts
      retry
    end

    destination.binwrite(response.body)
    spoken.bytesize # what Fish charges for
  end

  def seconds(path)
    out, status = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path.to_s)
    status.success? ? out.to_f.round(2) : nil
  end

  def run(prefixes)
    Voice::DIR.mkpath
    lines = Voice.lines
    redo_keys = prefixes.empty? ? [] : lines.map(&:key).select { |key| prefixes.any? { |prefix| key.start_with?(prefix) } }
    raise "No line has a key starting with #{prefixes.join(", ")}" if prefixes.any? && redo_keys.empty?

    sent = 0
    recorded = 0
    lines.each do |line|
      path = Voice.path(line.text)
      next if redo_keys.any? ? !redo_keys.include?(line.key) : path.exist?

      sent += record(line.text, path)
      recorded += 1
      puts "recorded #{line.key[0, 12]} #{line.source}: #{line.text.truncate(60)}"
    end

    keys = lines.map(&:key)
    Voice::DIR.glob("*.mp3").each do |file|
      next if keys.include?(file.basename(".mp3").to_s)

      file.delete
      puts "removed #{file.basename}"
    end

    write_manifest(lines)
    puts format("%d recorded, %d bytes of text, about $%.4f", recorded, sent, sent * DOLLARS_PER_MILLION_BYTES / 1_000_000)
  end

  # { "voice", "lines" => { key => { "text", "audio", "seconds" } } }, sorted by key so reruns don't reorder it.
  def write_manifest(lines)
    entries = lines.select { |line| Voice.path(line.text).exist? }.sort_by(&:key).to_h do |line|
      path = Voice.path(line.text)
      [ line.key, { "text" => line.text, "audio" => Digest::SHA256.file(path).hexdigest[0, 12], "seconds" => seconds(path) } ]
    end
    manifest = { "voice" => "One recorded synthetic voice (Fish Audio #{MODEL}), made by script/voice/generate.rb",
                 "lines" => entries }
    Voice::MANIFEST.write("#{JSON.pretty_generate(manifest)}\n")
  end
end

VoiceRecorder.run(ARGV)
