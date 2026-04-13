# frozen_string_literal: true

require "test_helper"

class TestReaderable < Minitest::Test
  FIXTURES = load_test_pages

  FIXTURES.each do |fixture|
    dir = fixture[:dir]
    safe_dir = dir.gsub("-", "_")
    expected = fixture[:expected_metadata]["readerable"]

    define_method("test_#{safe_dir}_readerable") do
      result = Readability.readerable?(fixture[:source])
      assert_equal expected, result, "#{dir}: readerable? should be #{expected}"
    end
  end

  def test_very_small_doc_not_readerable
    refute Readability.readerable?("<html><p>hello there</p></html>")
  end

  def test_small_doc_not_readerable
    refute Readability.readerable?("<html><p>#{"hello there " * 11}</p></html>")
  end

  def test_large_doc_not_readerable_with_defaults
    refute Readability.readerable?("<html><p>#{"hello there " * 12}</p></html>")
  end

  def test_very_large_doc_readerable
    assert Readability.readerable?("<html><p>#{"hello there " * 50}</p></html>")
  end

  def test_custom_min_content_length
    html = "<html><p>#{"hello there " * 11}</p></html>"
    assert Readability.readerable?(html, min_content_length: 120, min_score: 0)
  end

  def test_custom_visibility_checker_not_visible
    html = "<html><p>#{"hello there " * 50}</p></html>"
    refute Readability.readerable?(html, visibility_checker: ->(_) { false })
  end

  def test_custom_visibility_checker_visible
    html = "<html><p>#{"hello there " * 50}</p></html>"
    assert Readability.readerable?(html, visibility_checker: ->(_) { true })
  end
end
