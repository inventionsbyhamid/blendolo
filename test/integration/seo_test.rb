require "test_helper"

class SeoTest < ActionDispatch::IntegrationTest
  test "home has seo tags" do
    get "/"

    assert_response :success
    assert_select "title", "Blendolo: your favourite makeup look, in easier steps"
    assert_select "meta[name=description][content^='See your favourite look on your own photo']"
    assert_select "link[rel=canonical][href='https://blendolo.dijmo.com/']"
    assert_select "meta[property='og:image'][content^='https://blendolo.dijmo.com/assets/og']"
    assert_select "meta[name='twitter:card'][content=summary_large_image]"
    assert_select "meta[name=robots]", count: 0
    json_ld = JSON.parse(css_select("script[type='application/ld+json']").first.text)
    assert_equal %w[Organization WebApplication], json_ld["@graph"].map { |node| node["@type"] }
  end

  test "home has the landing page's own link preview lines" do
    get "/"

    assert_select "meta[property='og:description'][content^='The same red lip, without eleven tries.']"
    assert_select "meta[name='twitter:description'][content^='Makeup for hands that shake, tire or hurt.']"
  end

  test "the eyeliner guide quotes the ease engine" do
    get "/guides/eyeliner-with-a-tremor"

    profile = Ease::HandProfile.new
    wing = Ease::Scorer.step(Ease::StepCatalogue.fetch("liquid_liner_wing"), profile)
    pencil = Ease::Scorer.step(Ease::StepCatalogue.fetch("smudged_pencil_liner"), profile)
    assert_includes response.body, "scores #{wing} out of 100"
    assert_includes response.body, "A smudged pencil line scores #{pencil}."
  end

  test "the landing's example grades come from the ease engine" do
    get "/"

    rows = css_select(".float--swap .swaps li").map do |row|
      [ row.at_css(".swaps__was").text, row.css(".lvl").map(&:text), row.at_css(".swaps__now").text.sub(/\A\S+ becomes /, "") ]
    end
    assert_equal [
      [ "Liquid red lipstick", [ "Hard", "Easy" ], "Red tinted balm" ],
      [ "Winged liquid liner", [ "Hard", "Some care" ], "Shadow liner" ]
    ], rows
    assert_equal [ "Hard", "Some care" ], css_select(".float--grade .lvl").map(&:text)
    assert_select ".float--swap .lvl--care", "Some care"

    # The same words straight from the engine, for the example person's hands and look, and the steps named are the
    # ones the engine swaps to.
    person = Examples.fetch(PagesHelper::LANDING_EXAMPLE[:person])
    profile = Ease::HandProfile.new(**person.hands)
    look = Looks::Catalogue.fetch(person.chosen_look)
    assert_equal "Hard", Ease::Words.for(Ease::Scorer.look(look.ease_steps, profile)[:ease])
    assert_equal "Some care", Ease::Words.for(Ease::Scorer.look(look.easy_steps(profile).map(&:step), profile)[:ease])
    planned = look.plan(profile)[:swaps].to_h { |swap| [ swap[:from].id, swap[:to]&.id ] }
    PagesHelper::LANDING_EXAMPLE[:swaps].zip(rows) do |shown, (_was, (from, to), _now)|
      assert_equal shown[:to], planned.fetch(shown[:from])
      assert_equal from, Ease::Words.for(Ease::Scorer.step(Ease::StepCatalogue.fetch(shown[:from]), profile))
      assert_equal to, Ease::Words.for(Ease::Scorer.step(Ease::StepCatalogue.fetch(shown[:to]), profile))
    end
  end

  test "home title and description fit search results" do
    get "/"

    assert_operator css_select("title").first.text.length, :<, 60
    assert_operator css_select("meta[name=description]").first["content"].length, :<, 155
  end

  test "public pages have one h1, a canonical link and no json ld" do
    [ "/privacy", "/accessibility", "/sources", "/guides", "/guides/eyeliner-with-a-tremor" ].each do |path|
      get path

      assert_select "h1", count: 1
      assert_select "link[rel=canonical][href='https://blendolo.dijmo.com#{path}']"
      assert_select "script[type='application/ld+json']", count: 0
    end
  end

  test "guides are 300 to 600 words" do
    PagesController::GUIDES.each_key do |slug|
      get "/guides/#{slug}"

      words = css_select("article").first.text.split.size
      assert_includes 300..600, words, "#{slug} has #{words} words"
    end
  end

  test "sitemap lists the public pages" do
    get "/sitemap.xml"

    assert_response :success
    locs = Nokogiri::XML(response.body).remove_namespaces!.xpath("//loc").map(&:text)
    assert_includes locs, "https://blendolo.dijmo.com/"
    assert_includes locs, "https://blendolo.dijmo.com/guides/makeup-with-parkinsons"
    assert_includes locs, "https://blendolo.dijmo.com/accessibility"
  end

  test "manifest and service worker are served" do
    get "/manifest.json"
    assert_equal "Blendolo", JSON.parse(response.body)["name"]

    get "/service-worker.js"
    assert_response :success
    assert_includes response.body, "offline.html"
  end

  test "an unknown guide is not found" do
    get "/guides/no-such-guide"

    assert_response :not_found
  end
end
