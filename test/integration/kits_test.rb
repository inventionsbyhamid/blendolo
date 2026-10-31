require "test_helper"
require "support/kit_helpers"

class KitsTest < ActionDispatch::IntegrationTest
  include KitHelpers

  test "unknown token 404" do
    get "/k/not-a-real-token"
    assert_response :not_found

    get "/k/not-a-real-token/looks"
    assert_response :not_found
  end

  test "deleted kit 404" do
    kit = make_kit
    get kit_path(kit)
    assert_response :success

    delete kit_path(kit)
    assert_redirected_to root_path
    assert_not Kit.exists?(kit.id)

    get kit_path(kit)
    assert_response :not_found
    get kit_looks_path(kit)
    assert_response :not_found
  end

  test "deleting twice ends on the same page" do
    kit = make_kit
    delete kit_path(kit)
    delete kit_path(kit)

    assert_redirected_to root_path
    follow_redirect!
    assert_select ".flash", /Everything is deleted/
  end

  test "an expired kit is 404 even before the purge job runs" do
    kit = make_kit
    kit.update_columns(purge_after: 1.minute.ago)

    get kit_path(kit)
    assert_response :not_found
  end

  test "kit pages noindex" do
    kit = make_kit
    [ kit_path(kit), kit_looks_path(kit), kit_consent_path(kit), kit_hand_path(kit, 1), delete_kit_path(kit) ].each do |path|
      get path

      assert_response :success, path
      assert_select "meta[name=robots][content='noindex, nofollow']"
      assert_select "link[rel=canonical]", count: 0
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    end
  end

  test "a visit counts as activity" do
    kit = travel_to(3.days.ago) { make_kit }

    get kit_path(kit)
    assert_in_delta Time.current, kit.reload.last_active_at, 5
  end

  test "start makes a kit, remembers it and asks for consent" do
    assert_difference -> { Kit.count }, 1 do
      post start_path, params: { path: "helper" }
    end
    kit = Kit.last
    assert kit.helper?
    assert_redirected_to kit_consent_path(kit)
    assert_equal kit.token, signed_cookie(:blendolo_kit)
  end

  test "start twice in a row makes one kit" do
    assert_difference -> { Kit.count }, 1 do
      post start_path, params: { path: "self_use" }
      post start_path, params: { path: "self_use" }
    end
  end

  test "photos require consent" do
    kit = make_kit(consented: false, photo: false)

    assert_no_difference -> { Photo.count } do
      post kit_photos_path(kit), params: { image: photo_upload, kind: "today" }
    end
    assert_redirected_to kit_consent_path(kit)

    get new_kit_photo_path(kit)
    assert_redirected_to kit_consent_path(kit)
    get kit_looks_path(kit)
    assert_redirected_to kit_consent_path(kit)
  end

  test "consent then a photo: stored as a jpeg no larger than 1600 px, sampled colours kept" do
    kit = make_kit(consented: false, photo: false)
    post kit_consent_path(kit), params: { retention_days: 7 }
    assert kit.reload.consented_at?
    assert_equal 7, kit.retention_days

    post kit_photos_path(kit), params: { image: photo_upload("face.png", "image/png"), kind: "today",
      sampled: { lips: "#a84452", skin: "#C99A7A", nose: "#000000" }.to_json }
    photo = kit.photos.today.last
    assert_redirected_to kit_looks_path(kit)
    assert_equal "image/jpeg", photo.image.content_type
    assert_equal({ "lips" => "#A84452", "skin" => "#C99A7A" }, photo.sampled)
    assert_equal [ 96, 120 ], [ photo.width, photo.height ]
  end

  test "the same photo sent twice is stored once" do
    kit = make_kit(photo: false)

    assert_difference -> { kit.photos.count }, 1 do
      2.times { post kit_photos_path(kit), params: { image: photo_upload, kind: "today" } }
    end
  end

  test "a file that isn't a photo is refused" do
    kit = make_kit(photo: false)

    post kit_photos_path(kit), params: { image: photo_upload("not_a_photo.jpg"), kind: "today" }
    assert_response :unprocessable_content
    assert_equal 0, kit.photos.count
    # A page shown for a POST has no GET address to come back to: My hands today goes back by the referer instead.
    assert_select "form[action=?] input[name=return_to]", kit_hands_today_path(kit), count: 0
  end

  test "hand answers are saved one screen at a time" do
    kit = make_kit(photo: false)

    patch kit_hand_path(kit, 1), params: { answer: 2 }
    assert_redirected_to kit_hand_path(kit, 2)
    patch kit_hand_path(kit, 5), params: { answer: 1 }
    assert_redirected_to new_kit_photo_path(kit)
    assert_equal [ 2, 1 ], [ kit.reload.tremor, kit.near_vision ]

    patch kit_hand_path(kit, 3), params: { answer: 9 }
    assert_nil kit.reload.one_hand
  end

  test "my hands today sets the size and goes back" do
    kit = make_kit

    patch kit_hands_today_path(kit), params: { hands_today: 2, return_to: kit_looks_path(kit) }
    assert_redirected_to kit_looks_path(kit)
    assert_equal 2, kit.reload.hands_today

    get kit_path(kit)
    assert_select "body[data-hands='2']"
  end

  test "kit home and the looks list lead to the signature look" do
    kit = make_kit

    [ kit_path(kit), kit_looks_path(kit) ].each do |page|
      get page
      assert_select "a[href=?]", kit_signature_path(kit), text: /Bring back your signature look/
      assert_select "p", text: /Use an old photo of your favourite look\. We rebuild it from easy steps\./
    end

    helper = make_kit(path: :helper)
    get kit_path(helper)
    assert_select "a[href=?]", kit_signature_path(helper), text: /Bring back their signature look/
  end

  test "every kit page has its own title and stays out of search" do
    kit = make_kit(tremor: 2, pinch: 1, one_hand: 0, fatigue: 1, near_vision: 1)
    post kit_routine_path(kit), params: { look_key: "red_lip" }
    pages = [
      kit_path(kit), kit_consent_path(kit), *(1..5).map { |number| kit_hand_path(kit, number) }, new_kit_photo_path(kit),
      new_kit_photo_path(kit, kind: "reference"), kit_looks_path(kit), kit_look_path(kit, "red_lip"),
      kit_look_path(kit, "everyday_fresh"), kit_routine_path(kit), step_kit_routine_path(kit, 1),
      step_kit_routine_path(kit, 2), print_kit_routine_path(kit), kit_shopping_path(kit), kit_shares_path(kit),
      kit_signature_path(kit), delete_kit_path(kit)
    ]

    titles = pages.map do |page|
      get page
      assert_response :success, page
      assert_select "meta[name=robots][content='noindex, nofollow']"
      css_select("title").first.text
    end
    assert_equal titles.uniq, titles, titles.tally.select { |_title, count| count > 1 }.inspect
    assert titles.all? { |title| title.end_with?(" | Blendolo") }, titles.inspect
    assert_includes titles, "The red lip, your easy version | Blendolo"
    assert_includes titles, "Do your hands shake? | Blendolo"
  end

  test "the capture page has no picture without a source" do
    get new_kit_photo_path(make_kit)

    assert_response :success
    assert_select "img:not([src])", count: 0
    assert_select "img[src='']", count: 0
  end
end
