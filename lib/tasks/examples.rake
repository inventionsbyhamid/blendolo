namespace :examples do
  desc "Build fresh example kits from config/blendolo/examples.yml (older ones expire on their own)"
  task rebuild: :environment do
    Examples.keys.each do |key|
      kit = Examples.rebuild!(key)
      puts "#{key}: built a new example kit with #{kit.photos.count} photos and #{kit.renders.count} previews"
    end
  end
end
