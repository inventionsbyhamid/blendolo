# The example people's kits (config/blendolo/examples.yml). Safe to run again: a kit that is still alive is reused.
Examples.keys.each { |key| Examples.kit_for(key) }
