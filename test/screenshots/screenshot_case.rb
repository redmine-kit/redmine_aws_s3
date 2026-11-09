# frozen_string_literal: true

require File.expand_path('../../../../test/application_system_test_case', __dir__)

# Takes the screenshots of the docs (bin/screenshots): each screen in English
# into docs/images/ and in Japanese into docs/ja/images/, cropped to an
# element of the page. Redmine's test data (fixtures) fills the screens.
class ScreenshotCase < ApplicationSystemTestCase
  DOCS = File.expand_path('../../docs', __dir__)
  LANGUAGES = { 'en' => 'images', 'ja' => 'ja/images' }.freeze

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :trackers, :projects_trackers,
           :enabled_modules, :issue_statuses, :issues, :enumerations, :custom_fields, :custom_values,
           :custom_fields_trackers, :watchers, :journals, :journal_details, :workflows, :versions,
           :issue_categories

  def setup
    page.driver.browser.manage.window.resize_to(1280, 900)
  end

  # Runs the block once per language, logged in as the administrator with
  # that language.
  def each_language
    LANGUAGES.each_key do |language|
      User.find(1).update!(language: language)
      Capybara.reset_sessions!
      page.driver.browser.manage.window.resize_to(1280, 900)
      log_user('admin', 'admin')
      yield language
    end
  end

  # Hides the siblings after the element, to keep a screenshot to the part
  # the docs describe.
  def hide_after(selector)
    page.execute_script(<<~JS)
      var node = document.querySelector(#{selector.to_json});
      while (node && (node = node.nextElementSibling)) { node.style.display = 'none'; }
    JS
  end

  # Saves the element (by default Redmine's content area) as
  # docs/<images>/<name>.png.
  # The window grows to the element's height first, since Chrome only
  # captures what is in the window; the focused field loses its caret.
  def shoot(name, language, selector: '#content')
    element = page.find(selector)
    # Grow the window to the whole page: Redmine's #content stretches to the
    # window, so the page's own height is measured, until it stops growing.
    3.times do
      height = page.evaluate_script('document.documentElement.scrollHeight')
      break if height <= page.evaluate_script('window.innerHeight')

      page.driver.browser.manage.window.resize_to(1280, height + 200)
    end
    page.execute_script('window.scrollTo(0, 0); document.activeElement?.blur()')
    path = File.join(DOCS, LANGUAGES.fetch(language), "#{name}.png")
    element.native.save_screenshot(path)
    assert File.size?(path), "no screenshot at #{path}"
  end
end
