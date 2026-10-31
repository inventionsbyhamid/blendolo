# Records Blendolo's voice lines (Voice.lines) with Fish Audio text to speech: one mp3 per line in public/voice,
# named by the line's key, and public/voice/manifest.json. A line that already has a file is skipped, so a rerun only
# records new or changed lines; delete a file (or name its key) to record it again. Files of lines no longer in the
# list are removed.
#
#   FISH_AUDIO_API_KEY=... FISH_VOICE_ID=... bin/rails runner script/voice/generate.rb [key prefix ...]
#
# With key prefixes, only those lines are recorded (again, if they have a file). The key and the voice come from the
# environment only. Joining sentences and durations need ffmpeg and ffprobe.
#
# The voice is calm, warm and clear: the listener is in the middle of a task. Fish S2 reads an emotion tag in square
# brackets at the start of a sentence, and the tags go only into the request: the app shows and stores the plain
# words. The voice speaks at its own speed: Fish's prosody speed stretches the audio, which costs quality. mp3 at
# 128 kbps, mono: 64 kbps (Fish's lowest) sounds worse for speech.
require "net/http"
require "json"
require "open3"
require "tmpdir"

module VoiceRecorder
  ENDPOINT = URI("https://api.fish.audio/v1/tts")
  MODEL = "s2.1-pro".freeze
  # Fish's price for this model, per million UTF-8 bytes of text sent (docs.fish.audio, October 2026).
  DOLLARS_PER_MILLION_BYTES = 15.0
  SETTINGS = { format: "mp3", sample_rate: 44_100, mp3_bitrate: 128, temperature: 0.6, top_p: 0.7, latency: "normal",
               language: "en", normalize: true, prosody: { speed: 1.0, volume: 0, normalize_loudness: true } }.freeze

  # Words said differently from how they're written.
  SPOKEN = { "1" => "One.", "2" => "Two.", "3" => "Three.", "4" => "Four.", "5" => "Five.", "6" => "Six.",
             "7" => "Seven.", "8" => "Eight.", "9" => "Nine.", "10" => "Ten." }.freeze
  SPELLINGS = { /\bBlendolo\b/ => "Blend-oh-loh" }.freeze

  # Real silence between a line's sentences: the voice's own pauses are short (0.2 to 0.5 s), and someone in the
  # middle of a step needs a moment between instructions. A little longer before a new part of a card: the
  # instruction after the optional line, "Why this is easier" and "Tip".
  PAUSE = 0.7
  PART_PAUSE = 0.9
  PARTS = /(?<=#{Regexp.escape(Ease::Step::OPTIONAL_WHY)}) | (?=Why this is easier: |Tip: )/
  # Each sentence keeps 0.05 s of its own room tone before the words and 0.1 s after, and fades in and out over
  # 10 ms, so the joins don't click.
  TRIM = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse," \
         "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,afade=t=in:d=0.01,areverse," \
         "afade=t=in:d=0.01".freeze

  module_function

  # A line as takes, one per sentence: [{ speech:, pause: seconds of silence before it }]. Each take's text starts
  # with one tag: calm for what to do, warm for why it's easier and for "Got it", encouraging for the tip.
  def takes(text)
    return [ { speech: SPOKEN.fetch(text), pause: 0 } ] if SPOKEN.key?(text)

    words = SPELLINGS.reduce(text) { |spoken, (pattern, spelling)| spoken.gsub(pattern, spelling) }
    words.split(PARTS).each_with_index.flat_map do |part, part_index|
      part_tag = { "Why this is easier: " => "[warm]", "Tip: " => "[encouraging]" }.find { |start, _| part.start_with?(start) }&.last
      part.split(/(?<=[.!?]) +/).each_with_index.map do |sentence, index|
        tag = sentence.start_with?("Got it") ? "[warm]" : part_tag || "[calm]"
        pause = index.positive? ? PAUSE : (part_index.positive? ? PART_PAUSE : 0)
        { speech: "#{tag} #{sentence}", pause: }
      end
    end
  end

  # One sentence takes one request, straight to mp3. Several are recorded one by one (as wav, so they're encoded
  # once) and joined with real silence (join).
  def record(text, destination)
    pieces = takes(text)
    if pieces.one?
      destination.binwrite(tts(pieces.first[:speech], "mp3"))
    else
      audio = pieces.map { |piece| Thread.new { tts(piece[:speech], "wav") } }.map(&:value)
      Dir.mktmpdir do |dir|
        files = audio.each_with_index.map { |bytes, index| File.join(dir, "#{index}.wav").tap { |file| File.binwrite(file, bytes) } }
        join(files, pieces.map { |piece| piece[:pause] }, destination)
      end
    end
    pieces.sum { |piece| piece[:speech].bytesize } # what Fish charges for
  end

  def join(files, pauses, destination)
    chains = files.each_index.map do |index|
      pad = index < files.size - 1 ? ",apad=pad_dur=#{pauses[index + 1]}" : ""
      "[#{index}:a]aformat=sample_rates=44100:channel_layouts=mono,#{TRIM}#{pad}[p#{index}]"
    end
    graph = "#{chains.join(";")};#{files.each_index.map { |index| "[p#{index}]" }.join}concat=n=#{files.size}:v=0:a=1[out]"
    system("ffmpeg", "-v", "error", "-y", *files.flat_map { |file| [ "-i", file ] }, "-filter_complex", graph,
           "-map", "[out]", "-map_metadata", "-1", "-fflags", "+bitexact", "-c:a", "libmp3lame", "-b:a", "128k", "-ac", "1",
           "-ar", "44100", destination.to_s, exception: true)
  end

  def tts(speech, format)
    body = SETTINGS.merge(format:, text: speech, reference_id: ENV.fetch("FISH_VOICE_ID")).to_json
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
    response.body
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
