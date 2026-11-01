require "application_system_test_case"
require "support/kit_helpers"
require "support/account_helpers"

class LooksSystemTest < ApplicationSystemTestCase
  include KitHelpers
  include AccountHelpers

  setup do
    @kit = make_kit(tremor: 2, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 1)
  end

  test "looks sorted easiest first for tremor profile" do
    on_phone { visit kit_looks_path(@kit) }

    expected = LookForKit.easiest_first(@kit)
    assert_equal expected.map(&:name), all(".tiles--looks .tile__label").map(&:text)
    expected.zip(all(".tiles--looks .tile__badge")) do |look, badge|
      pattern = look.classic_words == look.easy_words ? /#{look.easy_words}/ : /#{look.classic_words}.*\u2192.*#{look.easy_words}/m
      assert_match(pattern, badge.text)
    end
    eases = expected.map { |look| look.classic_ease[:ease] }
    assert_equal eases.sort.reverse, eases
    assert_selector ".tiles--looks .tile__hint", text: "Hardest step you need:", minimum: 1
    shot "looks"
  end

  test "signed out, the look page asks for a sign in, then shows the price, then classic and easy" do
    visit kit_look_path(@kit, "red_lip")
    assert_selector ".spend", text: "Sign in to see this on your face. Free for your first look."
    assert_no_button "Show it on my face"
    mock_google(name: "Rosa Diaz")
    click_on "Sign in with Google"

    # Back on the same look, with the free credits and the price before anything is spent.
    assert_selector "h1", text: LookForKit.find(@kit, "red_lip").name
    assert_selector ".flash", text: "You're signed in, Rosa."
    assert_selector ".spend__words", text: "Uses 2 credits. You have 2."
    assert_equal 0, @kit.renders.count
    click_on "Show it on my face"
    assert_selector "[id^=render_]", count: 2, wait: 10
    assert_no_selector ".spend"
    assert_equal 0, Credits.balance(User.sole)
    assert_equal User.sole, @kit.reload.user
    classic, easy = @kit.renders.order(:id).to_a
    assert_equal %w[classic easy], [ classic.kind, easy.kind ]
    assert_selector "##{dom_id(classic)}", text: "This takes about half a minute. If it takes longer, this page checks again by itself."

    [ classic, easy ].each do |render|
      render.result.attach(io: file_fixture("face.jpg").open, filename: "#{render.kind}.jpg", content_type: "image/jpeg")
      render.update!(status: :done)
    end
    on_phone { visit kit_look_path(@kit, "red_lip") }

    within(".compare") do
      assert_selector "##{dom_id(classic)} img.render__image"
      assert_selector "##{dom_id(easy)} img.render__image"
      assert_text "Preview, not a promise"
      click_on "Easy", exact: true
      assert_selector ".compare__stage[data-show=easy]"
      assert_no_selector "##{dom_id(classic)} img", visible: true
    end
    assert_selector ".ease-change", text: "\u2192"
    shot "look"
  end

  test "a preview on its way shows up without a live update" do
    photo = @kit.photos.today.sole
    look = LookForKit.find(@kit, "red_lip")
    renders = { classic: look.classic_effects(photo), easy: look.easy_effects(photo) }.map do |kind, effects|
      @kit.renders.create!(Previews.attributes(photo, "red_lip", kind, effects, nil).merge(status: :running, started_at: Time.current))
    end
    visit kit_look_path(@kit, "red_lip")
    assert_selector ".render--running", text: "This takes about half a minute", count: 2
    history = evaluate_script("history.length")

    # Done, with no broadcast: only the page's own reload (every 20 s) can show it.
    renders.each do |render|
      render.result.attach(io: file_fixture("face.jpg").open, filename: "#{render.kind}.jpg", content_type: "image/jpeg")
      render.update!(status: :done)
    end
    assert_selector "img.render__image", count: 2, wait: 30
    assert_equal history, evaluate_script("history.length"), "the reload replaces the page in history"
    assert_nil evaluate_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('main'), 'refresh').timer"),
      "nothing left on its way, so no more reloads"
  end

  test "the page waits to reload while a tap is on its way or the device is offline" do
    photo = @kit.photos.today.sole
    look = LookForKit.find(@kit, "red_lip")
    # Both previews asked for already, so the page doesn't ask (and move on) by itself.
    { classic: look.classic_effects(photo), easy: look.easy_effects(photo) }.each do |kind, effects|
      @kit.renders.create!(Previews.attributes(photo, "red_lip", kind, effects, nil).merge(status: :running, started_at: Time.current))
    end
    visit kit_look_path(@kit, "red_lip")
    assert_selector ".render--running", text: "This takes about half a minute", count: 2
    assert_no_selector "form[data-controller=autostart]"
    refresh = "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('main'), 'refresh')"
    execute_script %(document.querySelector("main").insertAdjacentHTML("beforeend", '<p id="before-reload">here</p>'))

    # A held control: no reload now, another try at the next tick.
    execute_script %(document.querySelector("main").insertAdjacentHTML("beforeend", '<button id="held" class="is-working" aria-busy="true">Working on it</button>'))
    execute_script "#{refresh}.refresh()"
    sleep 0.5
    assert_selector "#before-reload"
    assert evaluate_script("#{refresh}.timer != null"), "tries again at the next tick"

    # Offline: the same.
    execute_script %(document.getElementById("held").remove(); Object.defineProperty(navigator, "onLine", { get: () => false, configurable: true }))
    execute_script "#{refresh}.refresh()"
    sleep 0.5
    assert_selector "#before-reload"

    # Back online with nothing held: it reloads.
    execute_script "delete navigator.onLine; #{refresh}.refresh()"
    assert_no_selector "#before-reload"
    assert_selector ".render--running", text: "This takes about half a minute", count: 2
  end

  test "swaps listed in plain words" do
    visit kit_look_path(@kit, "red_lip")
    look = LookForKit.find(@kit, "red_lip")

    within(".swaplist") do
      look.swaps.each do |swap|
        assert_text swap[:from].name
        assert_text swap[:to]&.name || "Left out"
      end
      assert_text "Why it's easier:"
    end
    look.unswappable.each { |step| assert_text step.no_swap_why }
  end

  test "make routine" do
    visit kit_look_path(@kit, "red_lip")
    click_on "Make this my routine"

    assert_selector "h1", text: "Your routine"
    assert_equal "red_lip", @kit.reload.chosen_look_key
    assert_equal "fixup", @kit.routine.last["step"]
    assert_selector ".linklist li", count: @kit.routine.size
  end

  private
    def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

    def on_phone
      page.current_window.resize_to(390, 844)
      yield
    end

    teardown { page.current_window.resize_to(1400, 1400) }
end
