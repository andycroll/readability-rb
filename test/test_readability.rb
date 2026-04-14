# frozen_string_literal: true

require "test_helper"

class TestReadability < Minitest::Test
  FIXTURES = load_test_pages
  PARSE_RESULTS = {}

  def self.parse_result_for(fixture)
    PARSE_RESULTS[fixture[:dir]] ||= Readability.parse(
      fixture[:source],
      url: "http://fakehost/test/page.html",
      classes_to_preserve: ["caption"]
    )
  end

  def assert_metadata_equal(expected, actual, msg)
    if expected.nil?
      assert_nil actual, msg
    else
      assert_equal expected, actual, msg
    end
  end

  FIXTURES.each do |fixture|
    dir = fixture[:dir]
    # Sanitize dir name for method names (replace hyphens with underscores)
    safe_dir = dir.gsub("-", "_")

    define_method("test_#{safe_dir}_returns_result") do
      result = self.class.parse_result_for(fixture)
      refute_nil result, "#{dir}: parse should return a result"
    end

    define_method("test_#{safe_dir}_extracts_content") do
      result = self.class.parse_result_for(fixture)
      skip "#{dir}: parse returned nil" if result.nil?
      compare_dom(result.content, fixture[:expected_content], dir)
    end

    define_method("test_#{safe_dir}_extracts_title") do
      result = self.class.parse_result_for(fixture)
      skip "#{dir}: parse returned nil" if result.nil?
      assert_metadata_equal fixture[:expected_metadata]["title"], result.title, "#{dir}: title"
    end

    define_method("test_#{safe_dir}_extracts_byline") do
      result = self.class.parse_result_for(fixture)
      skip "#{dir}: parse returned nil" if result.nil?
      assert_metadata_equal fixture[:expected_metadata]["byline"], result.byline, "#{dir}: byline"
    end

    define_method("test_#{safe_dir}_extracts_excerpt") do
      result = self.class.parse_result_for(fixture)
      skip "#{dir}: parse returned nil" if result.nil?
      assert_metadata_equal fixture[:expected_metadata]["excerpt"], result.excerpt, "#{dir}: excerpt"
    end

    define_method("test_#{safe_dir}_extracts_site_name") do
      result = self.class.parse_result_for(fixture)
      skip "#{dir}: parse returned nil" if result.nil?
      assert_metadata_equal fixture[:expected_metadata]["siteName"], result.site_name, "#{dir}: site_name"
    end

    if fixture[:expected_metadata]["dir"]
      define_method("test_#{safe_dir}_extracts_direction") do
        result = self.class.parse_result_for(fixture)
        skip "#{dir}: parse returned nil" if result.nil?
        assert_equal fixture[:expected_metadata]["dir"], result.dir, "#{dir}: dir"
      end
    end

    if fixture[:expected_metadata]["lang"]
      define_method("test_#{safe_dir}_extracts_language") do
        result = self.class.parse_result_for(fixture)
        skip "#{dir}: parse returned nil" if result.nil?
        assert_equal fixture[:expected_metadata]["lang"], result.lang, "#{dir}: lang"
      end
    end

    if fixture[:expected_metadata]["publishedTime"]
      define_method("test_#{safe_dir}_extracts_published_time") do
        result = self.class.parse_result_for(fixture)
        skip "#{dir}: parse returned nil" if result.nil?
        assert_equal fixture[:expected_metadata]["publishedTime"], result.published_time,
          "#{dir}: publishedTime"
      end
    end
  end
end
