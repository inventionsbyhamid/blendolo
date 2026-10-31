require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  test "every line has a recording" do
    missing = Voice.lines.reject { |line| Voice.path(line.text).exist? }
    assert_empty missing.map(&:source), "Record them with script/voice/generate.rb"
  end

  test "every step card and every photo prompt is a line" do
    keys = Voice.lines.map(&:key)
    Ease::StepCatalogue.all.each { |step| assert_includes keys, Voice.key(Voice.card(step)), step.id }
    Voice.optional_steps.each { |step| assert_includes keys, Voice.key(Voice.card(step)), "#{step.id}, optional" }
    Voice.capture_lines.each { |text| assert_includes keys, Voice.key(text), text }
  end

  test "the manifest matches the files" do
    manifest = Voice.manifest
    assert_equal Voice.lines.map(&:key).sort, manifest.keys.sort, "manifest lines"

    files = Voice::DIR.glob("*.mp3").map { |file| file.basename(".mp3").to_s }
    assert_equal manifest.keys.sort, files.sort, "one file per manifest line, no others"

    manifest.each do |key, entry|
      file = Voice::DIR.join("#{key}.mp3")
      assert_equal key, Voice.key(entry["text"]), "the key is the text's"
      assert_equal entry["audio"], Digest::SHA256.file(file).hexdigest[0, 12], "#{entry["text"]}: audio digest"
      assert_operator entry["seconds"], :>, 0.3, entry["text"]
      first = file.binread(3)
      assert first == "ID3" || first.bytes.first(2) == [ 0xFF, 0xFB ], "#{entry["text"]}: an mp3"
    end
  end

  test "the recordings stay small" do
    total = Voice::DIR.glob("*.mp3").sum(&:size)
    assert_operator total, :<, 10.megabytes
  end

  test "the photo page's spoken lines are all listed" do
    gate = Rails.root.join("app/javascript/capture/gate.js").read
    messages = gate[/export const MESSAGES = \{(.*?)\n\}/m, 1].scan(/^\s+(\w+): "(.*)",?$/).to_h
    assert_operator messages.size, :>=, 8
    # The eyes note is only shown on its own; it's said as part of doneEyes.
    messages.except("eyesNote").each_value { |text| assert_includes Voice::CAPTURE, text }

    capture = Rails.root.join("app/javascript/controllers/capture_controller.js").read
    %w[NO_CHECKS CHECKING NO_FACE].each do |name|
      text = capture[/^const #{name} = "(.*)"$/, 1]
      assert text, "#{name} in capture_controller.js"
      assert_includes Voice::CAPTURE, text
    end

    seconds = Rails.root.join("app/views/photos/new.html.erb").read.scan(/data-capture-seconds-param="(\d+)"/).flatten.map(&:to_i)
    assert_operator seconds.size, :>=, 2
    assert_operator seconds.max, :<=, Voice::COUNTDOWN.size
  end

  test "normalize tidies spaces, and the key is the SHA-256 of the tidied text" do
    assert_equal "Got it", Voice.normalize("  Got\n  it \t")
    assert_equal Digest::SHA256.hexdigest("Got it"), Voice.key(" Got  it ")
    assert_equal "5ad3dbd1242a4cea217e8b68a9fd2c8187f2c337258279193f6d9a31a9f1a69c", Voice.key("Got it")
  end

  test "a card's paragraphs are joined with full stops, as the page joins them" do
    assert_equal "One. Two! Three?", Voice.join([ " One", "", "Two!", "Three?\n" ])
    balm = Ease::StepCatalogue.fetch("tinted_balm")
    assert_equal "Dab the balm on your lips and press them together. Why this is easier: Sheer colour you can dab on " \
                 "with a finger. No edge to follow, and it blends itself. Tip: Press your lips together to spread it.", Voice.card(balm)
    assert Voice.card(balm.as_optional).start_with?("Optional. Skip it on shaky days. Dab the balm")
  end

  test "versions gives the audio digest of the texts that have a recording" do
    versions = Voice.versions([ "Got it", "Never recorded" ])
    assert_equal [ Voice.key("Got it") ], versions.keys
    assert_match(/\A\h{12}\z/, versions.values.first)
  end
end
