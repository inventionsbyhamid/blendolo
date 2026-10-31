namespace :voice do
  desc "List every line Blendolo reads aloud: key, recorded or missing, where it comes from, and the text"
  task lines: :environment do
    Voice.lines.each do |line|
      puts [ line.key, Voice.manifest.key?(line.key) ? "recorded" : "missing", line.source, line.text ].join("\t")
    end
  end
end
