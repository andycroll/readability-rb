# frozen_string_literal: true

require "test_helper"

class TestAPI < Minitest::Test
  def sample_source
    load_test_pages.first[:source]
  end

  def test_parse_returns_result_with_expected_attributes
    result = Readability.parse(sample_source, url: "http://fakehost/test/page.html")
    assert_kind_of Readability::Result, result
    assert_respond_to result, :content
    assert_respond_to result, :title
    assert_respond_to result, :excerpt
    assert_respond_to result, :byline
    assert_respond_to result, :text_content
    assert_respond_to result, :length
    assert_respond_to result, :site_name
    assert_respond_to result, :published_time
    assert_respond_to result, :dir
    assert_respond_to result, :lang
  end

  def test_parse_with_max_elems_to_parse_raises
    html = "<html><body><div>yo</div></html>"
    assert_raises(RuntimeError) do
      doc = Nokogiri::HTML5(html)
      Readability::Document.new(doc, max_elems_to_parse: 1).parse
    end
  end

  def test_parse_with_keep_classes_false_strips_classes
    html = "<html><body><div class='article-content'><p class='custom'>#{"hello world. " * 100}</p></div></body></html>"
    result = Readability.parse(html, keep_classes: false)
    refute_nil result
    # "custom" should be stripped, only preserved classes remain
    refute_includes result.content, 'class="custom"' if result
  end

  def test_parse_with_keep_classes_true_preserves_classes
    html = "<html><body><div class='article-content'><p class='custom'>#{"hello world. " * 100}</p></div></body></html>"
    result = Readability.parse(html, keep_classes: true)
    refute_nil result
    assert_includes result.content, "custom" if result
  end

  def test_custom_allowed_video_regex
    html = "<html><body><p>#{"Lorem ipsum dolor sit amet. " * 50}</p>" \
           '<iframe src="https://mycustomdomain.com/embed"></iframe></body></html>'
    result = Readability.parse(html, char_threshold: 20, allowed_video_regex: /.*mycustomdomain\.com.*/)
    refute_nil result
    assert_includes result.content, "mycustomdomain.com" if result
  end

  def test_classes_to_preserve
    html = "<html><body><div><p class='caption'>#{"text content here. " * 100}</p></div></body></html>"
    result = Readability.parse(html, classes_to_preserve: ["caption"])
    refute_nil result
    assert_includes result.content, 'class="caption"' if result
  end

  def test_convenience_parse_with_url
    result = Readability.parse("<html><body><p>#{"hello world. " * 100}</p></body></html>", url: "http://example.com")
    refute_nil result
    assert_kind_of Readability::Result, result
  end

  def test_readerable_convenience_method
    assert Readability.readerable?("<html><p>#{"hello there " * 50}</p></html>")
    refute Readability.readerable?("<html><p>short</p></html>")
  end

  def test_parse_returns_text_content_and_length
    html = "<html><body><p>#{"This is test content. " * 50}</p></body></html>"
    result = Readability.parse(html)
    refute_nil result
    if result
      assert_kind_of String, result.text_content
      assert_kind_of Integer, result.length
      assert_equal result.text_content.length, result.length
      assert result.length > 0
    end
  end

  def test_parse_with_nil_result_for_empty_doc
    result = Readability.parse("<html><body></body></html>")
    # Empty doc may return nil
    assert_nil result
  end

  def test_max_attributes_kwarg_raises_when_exceeded
    junk = (1..80).map { |i| "a#{i}=b" }.join(" ")
    html = "<html><head><meta #{junk}></head>" \
           "<body><p>#{"hello world. " * 100}</p></body></html>"
    assert_raises(ArgumentError) { Readability.parse(html, max_attributes: 50) }
  end

  def test_max_attributes_kwarg_allows_higher_limit
    junk = (1..80).map { |i| "a#{i}=b" }.join(" ")
    html = "<html><head><meta #{junk}></head>" \
           "<body><p>#{"hello world. " * 100}</p></body></html>"
    result = Readability.parse(html, max_attributes: 200)
    refute_nil result
  end

  def test_document_accepts_nokogiri_doc
    doc = Nokogiri::HTML5("<html><body><p>#{"Test content. " * 100}</p></body></html>")
    result = Readability::Document.new(doc).parse
    refute_nil result
    assert_kind_of Readability::Result, result
  end
end
