require "application_system_test_case"

# The judge's path: the landing page, an example person, their looks, a look classic and easy, their signature
# look, a step card and the shopping list, all from stored previews: no provider call and no new render.
class ExampleFlowTest < ApplicationSystemTestCase
  teardown { page.current_window.resize_to(1400, 1400) }

  test "an example person end to end without the provider" do
    page.current_window.resize_to(390, 844)
    calls = ProviderCall.count

    visit root_path
    assert_selector "h1", text: "hands that shake"
    shot "integration-home"

    click_on "Start"
    click_on "Try with an example person"
    click_on "Rosa"
    assert_selector "h1", text: "Rosa's kit"
    assert_text "AI generated example person"
    kit = Examples.kit_for("rosa")
    # Opening the kit built it from the stored photos and previews; from here on nothing is added.
    renders = Render.count
    shot "integration-kit"

    within("main") { click_on "Looks" }
    assert_selector ".tiles--looks .tile__note", text: "AI generated", minimum: 1
    shot "integration-looks"

    find(".tiles--looks a", text: "The red lip").click
    assert_selector "h1", text: "The red lip"
    assert_selector ".compare img.render__image", count: 2
    shot "integration-look"

    click_on "All looks"
    click_on "Bring back your signature look"
    assert_current_path kit_signature_path(kit)
    assert_selector ".three-up img", count: 3
    shot "integration-signature"

    visit step_kit_routine_path(kit, 1)
    assert_selector ".step-zoom img.step-zoom__image"
    shot "integration-step-card"

    visit kit_shopping_path(kit)
    assert_selector ".honest", text: "Demo catalogue"
    shot "integration-shopping"

    assert_equal calls, ProviderCall.count
    assert_equal renders, Render.count
  end
end
