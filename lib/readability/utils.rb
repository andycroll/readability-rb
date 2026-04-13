# frozen_string_literal: true

module Readability
  module Utils
    private

    # Port of _removeNodes (JS line 304)
    # Iterates over a node list in reverse, removing nodes where the block
    # returns true (or all nodes if no block is given).
    def remove_nodes(node_list)
      node_list.to_a.reverse_each do |node|
        next unless node.parent

        if block_given?
          node.unlink if yield(node)
        else
          node.unlink
        end
      end
    end

    # Port of _replaceNodeTags (JS line 327)
    # Calls set_node_tag for each node in the list.
    def replace_node_tags(node_list, new_tag)
      node_list.each do |node|
        set_node_tag(node, new_tag)
      end
    end

    # Port of _getAllNodesWithTag (JS line 397)
    def get_all_nodes_with_tag(node, tag_names)
      node.css(tag_names.join(","))
    end

    # Port of _getInnerText (JS line 2084)
    def get_inner_text(element, normalize_spaces = true)
      text = element.text.strip
      text = text.gsub(NORMALIZE, " ") if normalize_spaces
      text
    end

    # Port of _isWhitespace (JS line 2068)
    def is_whitespace?(node)
      (node.text? && node.text.strip.empty?) ||
        (node.element? && node.name == "br")
    end

    # Port of _isPhrasingContent (JS line 2057)
    def is_phrasing_content?(node)
      node.text? ||
        PHRASING_ELEMS.include?(node.name) ||
        ((%w[a del ins].include?(node.name)) &&
          node.children.all? { |child| is_phrasing_content?(child) })
    end

    # Port of _hasSingleTagInsideElement (JS line 2013)
    def has_single_tag_inside_element?(element, tag)
      # There should be exactly 1 element child with given tag
      children = element.element_children
      return false if children.length != 1 || children[0].name != tag

      # And there should be no text nodes with real content
      !element.children.any? { |node| node.text? && HAS_CONTENT.match?(node.text) }
    end

    # Port of _isElementWithoutContent (JS line 2028)
    def is_element_without_content?(node)
      node.element? &&
        node.text.strip.empty? &&
        (node.element_children.empty? ||
          node.element_children.length ==
            node.css("br").length + node.css("hr").length)
    end

    # Port of _hasChildBlockElement (JS line 2044)
    def has_child_block_element?(element)
      element.children.any? do |node|
        DIV_TO_P_ELEMS.include?(node.name) || has_child_block_element?(node)
      end
    end

    # Port of _textSimilarity (JS line 981)
    def text_similarity(text_a, text_b)
      tokens_a = text_a.downcase.split(TOKENIZE).reject(&:empty?)
      tokens_b = text_b.downcase.split(TOKENIZE).reject(&:empty?)
      return 0 if tokens_a.empty? || tokens_b.empty?

      uniq_tokens_b = tokens_b.reject { |token| tokens_a.include?(token) }
      distance_b = uniq_tokens_b.join(" ").length.to_f / tokens_b.join(" ").length
      1.0 - distance_b
    end

    # Port of _isProbablyVisible (JS line 2720)
    # Checks inline style for display:none and visibility:hidden,
    # the hidden attribute, and aria-hidden="true" (with fallback-image exception).
    def is_probably_visible?(node)
      style = node["style"] || ""
      return false if style.match?(/display\s*:\s*none/i)
      return false if style.match?(/visibility\s*:\s*hidden/i)
      return false if !node["hidden"].nil?

      aria_hidden = node["aria-hidden"]
      if aria_hidden == "true"
        class_name = node["class"] || ""
        return false unless class_name.include?("fallback-image")
      end

      true
    end

    # Port of _nextNode (JS line 687)
    # Skip whitespace siblings to find next element-ish node.
    def next_node(node)
      current = node
      while current && !current.element? && WHITESPACE.match?(current.text)
        current = current.next_sibling
      end
      current
    end

    # Port of _getNextNode (JS line 959)
    # Depth-first traversal.
    def get_next_node(node, ignore_self_and_kids = false)
      # First check for kids if those aren't being ignored
      if !ignore_self_and_kids && node.element_children.first
        return node.element_children.first
      end

      # Then for siblings...
      return node.next_element if node.next_element

      # And finally, move up the parent chain *and* find a sibling
      current = node
      loop do
        current = current.parent
        break unless current && !current.next_element
      end
      current&.next_element
    end

    # Port of _removeAndGetNext (JS line 942)
    def remove_and_get_next(node)
      next_nd = get_next_node(node, true)
      node.unlink
      next_nd
    end

    # Port of _hasAncestorTag (JS line 2243)
    # max_depth of 0 means no limit.
    def has_ancestor_tag?(node, tag_name, max_depth = 3, &filter_fn)
      tag_name = tag_name.downcase
      depth = 0
      current = node
      while (parent = current.parent) && parent.element?
        return false if max_depth > 0 && depth > max_depth

        if parent.name == tag_name && (!filter_fn || filter_fn.call(parent))
          return true
        end
        current = parent
        depth += 1
      end
      false
    end

    # Port of _getNodeAncestors (JS line 1019)
    def get_node_ancestors(node, max_depth = 0)
      i = 0
      ancestors = []
      current = node
      while (parent = current.parent) && parent.element?
        ancestors << parent
        i += 1
        break if max_depth > 0 && i == max_depth
        current = parent
      end
      ancestors
    end

    # Port of _isSingleImage (JS line 1897)
    def is_single_image?(node)
      current = node
      while current
        return true if current.name == "img"
        return false if current.element_children.length != 1 || !current.text.strip.empty?

        current = current.element_children[0]
      end
      false
    end

    # Port of _isValidByline (JS line 1005)
    def is_valid_byline?(node, match_string)
      rel = node["rel"]
      itemprop = node["itemprop"]
      byline_text = node.text.strip

      return false if byline_text.empty? || byline_text.length >= 100

      rel == "author" ||
        (itemprop && itemprop.include?("author")) ||
        BYLINE.match?(match_string)
    end

    # Port of _isUrl (JS line 442)
    def is_url?(str)
      uri = URI.parse(str)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError, URI::InvalidComponentError
      false
    end
  end
end
