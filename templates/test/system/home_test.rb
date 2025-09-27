require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  def setup
    @page = @playwright_page
  end

  test "show welcome" do
    @page.goto(root_path)

    assert_includes @page.text_content("h1"), "Welcome"
  end
end
