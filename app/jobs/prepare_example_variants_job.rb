# Makes the resized pictures a new example kit's pages show, right after Examples builds it, so the judge's path
# through an example person doesn't wait for them. A failure only means the first visit makes them instead.
class PrepareExampleVariantsJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(kit)
    Examples.prepare_variants(kit)
  end
end
