require "test_helper"

class ExamplesTest < ActiveSupport::TestCase
  SEED = Rails.root.join("db/seeds/examples.rb")

  test "examples seed is idempotent" do
    load SEED
    kits = Kit.example.where(example_key: Examples.keys)
    assert_equal Examples.keys.sort, kits.map(&:example_key).sort
    assert_equal [ 6, 12 ], [ Photo.where(kit: kits).count, Render.where(kit: kits).count ]

    assert_no_difference [ "Kit.count", "Photo.count", "Render.count", "ActiveStorage::Blob.count" ] do
      load SEED
    end
  end

  test "every look has a thumbnail" do
    skip "needs Looks::Catalogue from the looks lane" unless defined?(Looks::Catalogue)

    Looks::Catalogue.all.each do |look|
      assert Rails.root.join("app/assets/images", look.thumbnail).file?, "#{look.key} has no #{look.thumbnail}"
    end
    Examples.all.each { |person| assert Looks::Catalogue.key?(person.chosen_look), person.key }
  end

  test "an example kit carries the person's hands, photos and finished renders" do
    kit = Examples.kit_for(:rosa)

    assert kit.example?
    assert_equal "rosa", kit.example_key
    assert_equal "red_lip", kit.chosen_look_key
    assert_equal Examples.fetch(:rosa).hands, kit.hand_answers
    assert kit.consented_at.present?
    assert_equal %w[reference today], kit.photos.map(&:kind).sort
    assert kit.photos.all? { it.image.attached? && it.source == "example" && it.sha256.present? }
    assert_equal %w[classic easy easy transfer], kit.renders.map(&:kind).sort
    assert kit.renders.all? { it.done? && it.result.attached? }
    assert_equal kit.photos.reference.sole, kit.renders.transfer.sole.reference_photo
  end

  test "a visitor reuses the living example kit, and gets a new one once it expired" do
    kit = Examples.kit_for("june")
    assert_equal kit, Examples.kit_for("june")
    assert_no_difference(-> { Kit.count }) { Examples.kit_for("june") }

    travel 31.days do
      fresh = Examples.kit_for("june")
      assert_not_equal kit, fresh
      assert fresh.purge_after.future?
    end
  end

  test "knows only its people" do
    assert_equal %w[rosa june amara], Examples.keys
    assert_raises(Examples::UnknownExample) { Examples.kit_for("bob") }
  end

  test "people's words follow the copy rules" do
    words = Examples.all.flat_map { [ it.name, it.blurb ] } << Examples.photo_label
    assert words.all?(&:present?)
    words.each { |text| assert_no_match(/[–—]/, text) }
  end
end
