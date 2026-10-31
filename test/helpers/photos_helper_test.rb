require "test_helper"

class PhotosHelperTest < ActionView::TestCase
  setup do
    @config = Rails.application.config.x
    @was = { capture_checks: @config.capture_checks, capture_worker: @config.capture_worker }
    @config.capture_checks = true
  end

  teardown { @was.each { |name, value| @config.public_send(:"#{name}=", value) } }

  test "the capture page gets MediaPipe's pinned URLs, the worker and the gates module" do
    @config.capture_worker = true
    urls = mediapipe_urls

    assert_equal @config.mediapipe.package_url, urls[:package_url]
    assert_equal @config.mediapipe.model_url, urls[:model_url]
    assert_match %r{/workers/face_checks(-\h+)?\.js\z}, urls[:worker_url]
    assert_match %r{/capture/gate(-\h+)?\.js\z}, urls[:gate_url]
  end

  test "with the worker switched off the page runs the checks itself" do
    @config.capture_worker = false

    assert_equal "", mediapipe_urls[:worker_url]
    assert_predicate mediapipe_urls[:package_url], :present?
  end

  test "with capture checks off there is nothing to load" do
    @config.capture_checks = false

    assert_equal({ package_url: "", model_url: "", worker_url: "", gate_url: "" }, mediapipe_urls)
  end
end
