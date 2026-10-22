# frozen_string_literal: true

require "test_helper"

class TestMetadata < Minitest::Test
  BODY = "<p>#{"Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 20}</p>"

  def page(head: "", body_prefix: "")
    "<html><head><title>Title</title>#{head}</head>" \
      "<body><article>#{body_prefix}#{BODY}#{BODY}</article></body></html>"
  end

  def json_ld(json)
    %(<script type="application/ld+json">#{json}</script>)
  end

  def parse(**kwargs)
    Readability.parse(page(**kwargs))
  end

  def test_json_ld_with_unexpected_shapes_is_skipped
    baseline = parse

    ["null", "5", "[null]", "[5]", '[{"@type":[{}]}]'].each do |json|
      result = parse(head: json_ld(json))

      assert_equal baseline.title, result.title, "title for #{json}"
      assert_nil result.byline, "byline for #{json}"
    end
  end

  def article_json_ld(fields)
    json_ld(JSON.generate({"@context" => "https://schema.org", "@type" => "NewsArticle"}.merge(fields)))
  end

  def test_json_ld_author_array_of_strings_is_ignored
    result = parse(head: article_json_ld("author" => ["Hannah Surname"]))

    assert_nil result.byline
  end

  def test_json_ld_author_array_of_strings_falls_back_to_meta_author
    head = article_json_ld("author" => ["Hannah Surname"]) +
      %(<meta name="author" content="Jane Smith">)

    assert_equal "Jane Smith", parse(head: head).byline
  end

  def test_json_ld_author_array_skips_string_items
    result = parse(head: article_json_ld("author" => [{"name" => "Jane Smith"}, "Hannah Surname"]))

    assert_equal "Jane Smith", result.byline
  end

  # Readability.js calls @type.match, which throws for an array, so it skips
  # the script. schema.org allows an array, so we accept it on purpose.
  def test_json_ld_type_array_is_accepted
    result = parse(head: article_json_ld("@type" => ["NewsArticle"], "author" => {"name" => "Jane Smith"}))

    assert_equal "Jane Smith", result.byline
  end

  def test_json_ld_type_array_in_graph_is_accepted
    json = JSON.generate(
      "@context" => "https://schema.org",
      "@graph" => [{"@type" => ["WebPage"]}, {"@type" => ["Thing", "Article"], "author" => {"name" => "Jane Smith"}}]
    )

    assert_equal "Jane Smith", parse(head: json_ld(json)).byline
  end

  def test_byline_element_trims_unicode_whitespace
    result = parse(body_prefix: %(<div class="byline"> By Jane Smith </div>))

    assert_equal "By Jane Smith", result.byline
  end

  def test_byline_element_with_item_prop_name_trims_unicode_whitespace
    byline = %(<div class="byline">By <span itemprop="name">　Jane Smith </span></div>)

    assert_equal "Jane Smith", parse(body_prefix: byline).byline
  end

  def test_json_ld_author_name_trims_unicode_whitespace
    assert_equal "Jane Smith", parse(head: article_json_ld("author" => {"name" => " Jane Smith "})).byline
    assert_equal "Jane Smith, John Doe",
      parse(head: article_json_ld("author" => [{"name" => " Jane Smith"}, {"name" => "John Doe﻿"}])).byline
  end

  def test_article_author_meta_ignores_urls
    ["https://example.com/jane", "mailto:jane@example.com", "urn:isbn:0451450523"].each do |url|
      result = parse(head: %(<meta property="article:author" content="#{url}">))

      assert_nil result.byline, "byline for #{url}"
    end
  end

  def test_article_author_meta_url_falls_back_to_meta_author
    head = %(<meta property="article:author" content="mailto:jane@example.com">) +
      %(<meta name="author" content="Jane Smith">)

    assert_equal "Jane Smith", parse(head: head).byline
  end

  def test_article_author_meta_accepts_names
    assert_equal "Jane Smith", parse(head: %(<meta property="article:author" content="Jane Smith">)).byline
  end

  # JS's URL constructor accepts "Jane: Smith" with the scheme "jane:", so
  # Readability.js ignores it. URI.parse rejects the space, so we keep it.
  def test_article_author_meta_with_colon_and_space_is_kept
    assert_equal "Jane: Smith", parse(head: %(<meta property="article:author" content="Jane: Smith">)).byline
  end

  def test_meta_author_trims_unicode_whitespace
    assert_equal "Jane Smith", parse(head: %(<meta name="author" content=" Jane Smith ">)).byline
    assert_equal "Jane Smith", parse(head: %(<meta property="article:author" content=" Jane Smith ">)).byline
  end
end
