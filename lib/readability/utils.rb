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
      css_query(node, tag_names.join(","))
    end

    # Same as node.css(selector). Node#css translates the selector to XPath and
    # sets up namespaces on every call, which costs more than running the query
    # on the small subtrees scoring and cleaning look at. This translates each
    # selector once per document type, the way Node#css does, and runs the
    # XPath directly. A Document searches from "//" rather than ".//", so it
    # keeps using css.
    def css_query(node, selector)
      return node.css(selector) if node.document?

      doctype = node.document.xpath_doctype
      xpath = (@xpath_cache[doctype] ||= {})[selector] ||= begin
        visitor = Nokogiri::CSS::XPathVisitor.new(
          builtins: Nokogiri::CSS::XPathVisitor::BuiltinsConfig::OPTIMAL,
          doctype: doctype,
          prefix: ".//",
        )
        Nokogiri::CSS.xpath_for(selector, visitor: visitor).join(" | ")
      end
      Nokogiri::XML::XPathContext.new(node).evaluate(xpath)
    end

    # JS-compatible trim that also strips Unicode whitespace like \u00A0 (NBSP)
    # JS's String.prototype.trim() strips all Unicode whitespace and \uFEFF (BOM).
    # Ruby's String#strip only removes ASCII whitespace.
    #
    # Finds the first and last non-space characters by byte offset (character
    # offsets in non-ASCII strings cost a scan from the start) instead of using
    # gsub(/\A\s+|\s+\z/), which rescans every interior whitespace run and is
    # quadratic on the long text of large elements.
    def js_trim(str)
      first = str.byteindex(NON_SPACE) or return ""
      str.byterindex(NON_SPACE)
      last = Regexp.last_match.byteoffset(0)[1]
      str.byteslice(first, last - first)
    end

    # Port of _getInnerText (JS line 2084)
    def get_inner_text(element, normalize_spaces = true)
      text = js_trim(element.text)
      text = text.gsub(NORMALIZE, " ") if normalize_spaces
      text
    end

    # Same as get_inner_text(element).length, for callers that only need the
    # length. tr_s collapses each whitespace run to one character, as NORMALIZE
    # does, at less than half the cost of the regex.
    def inner_text_length(element)
      js_trim(element.text).tr_s(SPACE_CHARS, " ").length
    end

    # Port of _isWhitespace (JS line 2068)
    def is_whitespace?(node)
      (node.text? && WHITESPACE.match?(node.text)) ||
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
      return false unless node.element?

      # Check the children first: reading the text walks the whole subtree.
      children = node.element_children
      (children.empty? || children.length == css_query(node, "br, hr").length) &&
        WHITESPACE.match?(node.text)
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
      if !ignore_self_and_kids && (first_child = node.first_element_child)
        return first_child
      end

      # Then for siblings...
      next_element = node.next_element
      return next_element if next_element

      # And finally, move up the parent chain *and* find a sibling
      current = node
      loop do
        break unless current.respond_to?(:parent) && current.parent
        current = current.parent
        break if current.next_element
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
        children = current.element_children
        return false if children.length != 1 || !WHITESPACE.match?(current.text)

        current = children[0]
      end
      false
    end

    # Port of _isValidByline (JS line 1005)
    def is_valid_byline?(node, match_string)
      itemprop = node["itemprop"]
      # Check the attributes before the text, which walks the whole subtree.
      return false unless node["rel"] == "author" ||
        (itemprop && itemprop.include?("author")) ||
        BYLINE.match?(match_string)

      byline_text = js_trim(node.text)
      !byline_text.empty? && byline_text.length < 100
    end

    # Port of _isUrl (JS line 442)
    # JS's URL constructor accepts any absolute URL, so any scheme counts.
    def is_url?(str)
      !URI.parse(str).scheme.nil?
    rescue URI::InvalidURIError, URI::InvalidComponentError
      false
    end
  end
end
