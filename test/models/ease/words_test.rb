require "test_helper"

class Ease::WordsTest < ActiveSupport::TestCase
  def test_words_boundaries
    assert_equal "Easy", Ease::Words.for(100)
    assert_equal "Easy", Ease::Words.for(80)
    assert_equal "Some care", Ease::Words.for(79)
    assert_equal "Some care", Ease::Words.for(60)
    assert_equal "Tricky", Ease::Words.for(59)
    assert_equal "Tricky", Ease::Words.for(40)
    assert_equal "Hard", Ease::Words.for(39)
    assert_equal "Hard", Ease::Words.for(0)
  end

  def test_every_step_tag_has_a_label
    Ease::StepCatalogue.all.flat_map(&:ease_tags).uniq.each do |tag|
      assert Ease::Words.tag(tag).present?, "label for #{tag}"
    end
  end
end
