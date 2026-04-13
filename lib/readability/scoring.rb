# frozen_string_literal: true

module Readability
  module Scoring
    private

    # Port of _initializeNode (JS line 903)
    # Sets up a node in @candidates with a base score derived from its tag name,
    # then adds the class/id weight.
    def initialize_node(node)
      base_score = case node.name
                   when "div"
                     5
                   when "pre", "td", "blockquote"
                     3
                   when "address", "ol", "ul", "dl", "dd", "dt", "li", "form"
                     -3
                   when "h1", "h2", "h3", "h4", "h5", "h6", "th"
                     -5
                   else
                     0
                   end

      @candidates[node] = { content_score: base_score + get_class_weight(node) }
    end

    # Port of _getClassWeight (JS line 2168)
    # Returns a weight based on the node's class and id attributes matching
    # POSITIVE or NEGATIVE regexps.
    def get_class_weight(node)
      return 0 unless flag_is_active?(FLAG_WEIGHT_CLASSES)

      weight = 0

      klass = node["class"]
      if klass && !klass.empty?
        weight -= 25 if NEGATIVE.match?(klass)
        weight += 25 if POSITIVE.match?(klass)
      end

      id = node["id"]
      if id && !id.empty?
        weight -= 25 if NEGATIVE.match?(id)
        weight += 25 if POSITIVE.match?(id)
      end

      weight
    end

    # Port of _getLinkDensity (JS line 2143)
    # Returns the ratio of anchor text length to total text length.
    # Fragment-only links (#...) count at 0.3 coefficient.
    def get_link_density(element)
      text_length = get_inner_text(element).length
      return 0 if text_length == 0

      link_length = 0.0

      element.css("a").each do |link_node|
        href = link_node["href"]
        coefficient = href && HASH_URL.match?(href) ? 0.3 : 1.0
        link_length += get_inner_text(link_node).length * coefficient
      end

      link_length / text_length
    end

    # Port of _getTextDensity (JS line 2440)
    # Returns the ratio of text inside elements matching +tags+ to total text in element.
    def get_text_density(element, tags)
      text_length = get_inner_text(element, true).length
      return 0 if text_length == 0

      children_length = 0
      get_all_nodes_with_tag(element, tags).each do |child|
        children_length += get_inner_text(child, true).length
      end

      children_length.to_f / text_length
    end

    # Port of _getCharCount (JS line 2102)
    # Counts occurrences of +separator+ in the element's inner text.
    def get_char_count(element, separator = ",")
      get_inner_text(element).split(separator).length - 1
    end

    # Returns the content score for a candidate node, defaulting to 0.
    def content_score(node)
      @candidates.dig(node, :content_score) || 0
    end

    # Sets the content score for a candidate node.
    def set_content_score(node, score)
      @candidates[node] ||= {}
      @candidates[node][:content_score] = score
    end
  end
end
