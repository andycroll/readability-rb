# frozen_string_literal: true

require "minitest/autorun"
require "readability"
require "json"
require "pathname"

TEST_PAGES_DIR = Pathname.new(File.expand_path("test-pages", __dir__))

def load_test_pages
  TEST_PAGES_DIR.children.select(&:directory?).sort.map do |dir|
    {
      dir: dir.basename.to_s,
      source: dir.join("source.html").read,
      expected_content: dir.join("expected.html").read,
      expected_metadata: JSON.parse(dir.join("expected-metadata.json").read),
    }
  end
end

# Normalize whitespace for text comparison
def html_transform(str)
  str.gsub(/\s+/, " ")
end

def node_description(node)
  return "(no node)" unless node
  return "#text(#{html_transform(node.text)})" if node.text?
  return "other:#{node.type}" unless node.element?

  desc = node.name
  desc += "##{node['id']}" if node['id'] && !node['id'].empty?
  desc += ".(#{node['class']})" if node['class'] && !node['class'].empty?
  desc
end

def sorted_attributes(node)
  return [] unless node&.element?
  node.attributes.values
    .map { |a| [a.name, a.value] }
    .sort_by(&:first)
end

# In-order DOM traversal, skipping whitespace-only text nodes
def next_significant_node(node)
  # Try first child
  candidate = if node.element? && node.children.any?
    node.children.first
  else
    # Try next sibling, or walk up to find one
    current = node
    while current && !current.next_sibling
      current = current.parent
    end
    current&.next_sibling
  end

  # Skip whitespace-only text nodes
  while candidate && candidate.text? && candidate.text.strip.empty?
    next_candidate = if candidate.next_sibling
      candidate.next_sibling
    else
      current = candidate
      while current && !current.next_sibling
        current = current.parent
      end
      current&.next_sibling
    end
    candidate = next_candidate
  end

  candidate
end

def compare_dom(actual_html, expected_html, test_name)
  actual_doc = Nokogiri::HTML5(actual_html)
  expected_doc = Nokogiri::HTML5(expected_html)

  # Start from the body's first element child (the readability wrapper div)
  actual_body = actual_doc.at_css("body")
  expected_body = expected_doc.at_css("body")

  actual_node = actual_body&.element_children&.first || actual_body&.children&.first
  expected_node = expected_body&.element_children&.first || expected_body&.children&.first

  while actual_node || expected_node
    actual_desc = node_description(actual_node)
    expected_desc = node_description(expected_node)

    assert_equal expected_desc, actual_desc,
      "#{test_name}: DOM node mismatch"

    if actual_node&.text?
      assert_equal html_transform(expected_node.text), html_transform(actual_node.text),
        "#{test_name}: Text content mismatch"
    elsif actual_node&.element?
      expected_attrs = sorted_attributes(expected_node)
      actual_attrs = sorted_attributes(actual_node)
      assert_equal expected_attrs, actual_attrs,
        "#{test_name}: Attributes mismatch on <#{actual_node.name}>"
    end

    actual_node = next_significant_node(actual_node)
    expected_node = next_significant_node(expected_node)
  end
end
