# frozen_string_literal: true

module Readability
  module Metadata
    private

    # Port of _unescapeHtmlEntities (JS line 1631-1651)
    # Replaces named HTML entities and numeric character references.
    def unescape_html_entities(str)
      return str unless str

      str
        .gsub(/&(quot|amp|apos|lt|gt);/) { HTML_ESCAPE_MAP[$1] }
        .gsub(/&#(?:x([0-9a-f]+)|([0-9]+));/i) do
          hex, num_str = $1, $2
          num = (hex || num_str).to_i(hex ? 16 : 10)

          # Replace invalid code points with U+FFFD
          if num == 0 || num > 0x10FFFF || (num >= 0xD800 && num <= 0xDFFF)
            num = 0xFFFD
          end

          [num].pack("U")
        end
    end

    # Port of _getJSONLD (JS line 1658-1773)
    # Extracts metadata from JSON-LD script tags with schema.org context.
    def get_json_ld(doc)
      scripts = get_all_nodes_with_tag(doc, ["script"])
      metadata = nil

      scripts.each do |json_ld_element|
        next if metadata
        next unless json_ld_element["type"] == "application/ld+json"

        begin
          # Strip CDATA markers if present
          content = json_ld_element.text.gsub(/\A\s*<!\[CDATA\[|\]\]>\s*\z/, "")
          parsed = JSON.parse(content)

          if parsed.is_a?(Array)
            parsed = parsed.find do |it|
              Array(it["@type"]).any? { |t| t.match?(JSON_LD_ARTICLE_TYPES) }
            end
            next unless parsed
          end

          schema_dot_org_regex = /\Ahttps?:\/\/schema\.org\/?\z/

          matches = (parsed["@context"].is_a?(String) &&
                      parsed["@context"].match?(schema_dot_org_regex)) ||
                    (parsed["@context"].is_a?(Hash) &&
                      parsed["@context"]["@vocab"].is_a?(String) &&
                      parsed["@context"]["@vocab"].match?(schema_dot_org_regex))

          next unless matches

          if !parsed["@type"] && parsed["@graph"].is_a?(Array)
            parsed = parsed["@graph"].find do |it|
              next unless it.is_a?(Hash)

              Array(it["@type"]).any? { |t| t.is_a?(String) && t.match?(JSON_LD_ARTICLE_TYPES) }
            end
          end

          next if !parsed || !parsed["@type"] || !Array(parsed["@type"]).any? { |t| t.is_a?(String) && t.match?(JSON_LD_ARTICLE_TYPES) }

          metadata = {}

          if parsed["name"].is_a?(String) && parsed["headline"].is_a?(String) &&
              parsed["name"] != parsed["headline"]
            # Both name and headline exist and differ — compare similarity to HTML title
            title = get_article_title
            name_matches = text_similarity(parsed["name"], title) > 0.75
            headline_matches = text_similarity(parsed["headline"], title) > 0.75

            if headline_matches && !name_matches
              metadata["title"] = parsed["headline"]
            else
              metadata["title"] = parsed["name"]
            end
          elsif parsed["name"].is_a?(String)
            metadata["title"] = parsed["name"].strip
          elsif parsed["headline"].is_a?(String)
            metadata["title"] = parsed["headline"].strip
          end

          if parsed["author"]
            if parsed["author"].is_a?(Hash) && parsed["author"]["name"].is_a?(String)
              metadata["byline"] = parsed["author"]["name"].strip
            elsif parsed["author"].is_a?(Array) &&
                parsed["author"][0] &&
                parsed["author"][0]["name"].is_a?(String)
              metadata["byline"] = parsed["author"]
                .select { |author| author && author["name"].is_a?(String) }
                .map { |author| author["name"].strip }
                .join(", ")
            end
          end

          if parsed["description"].is_a?(String)
            metadata["excerpt"] = parsed["description"].strip
          end

          if parsed["publisher"].is_a?(Hash) && parsed["publisher"]["name"].is_a?(String)
            metadata["site_name"] = parsed["publisher"]["name"].strip
          end

          if parsed["datePublished"].is_a?(String)
            metadata["date_published"] = parsed["datePublished"].strip
          end
        rescue JSON::ParserError => e
          # Handle malformed JSON gracefully
          log(e.message) if respond_to?(:log, true)
        end
      end

      metadata || {}
    end

    # Port of _getArticleTitle (JS line 573-661)
    # Extracts and cleans the article title from the document.
    def get_article_title
      cur_title = ""
      orig_title = ""

      begin
        cur_title = orig_title = (@doc.at_css("title")&.text&.strip || "")

        # If title came back as something other than a string (shouldn't happen
        # with Nokogiri, but match JS logic)
        if !cur_title.is_a?(String)
          cur_title = orig_title = get_inner_text(@doc.css("title").first)
        end
      rescue
        # ignore exceptions setting the title
      end

      title_had_hierarchical_separators = false
      word_count = ->(str) { str.split(/\s+/).length }

      # Title separator characters — exact JS source string from line 597
      title_separators = '\|\-\u2013\u2014\\\\\/>»'

      if cur_title.match?(/\s[#{title_separators}]\s/)
        title_had_hierarchical_separators = cur_title.match?(/\s[\\\/>\u00BB]\s/)

        # Find all separator positions and remove everything after the last one
        all_separators = orig_title.to_enum(:scan, /\s[#{title_separators}]\s/i).map { Regexp.last_match }
        cur_title = orig_title[0, all_separators.last.begin(0)]

        # If the resulting title is too short, remove the first part instead
        if word_count.call(cur_title) < 3
          cur_title = orig_title.sub(/\A[^#{title_separators}]*[#{title_separators}]/i, "")
        end
      elsif cur_title.include?(": ")
        # Check if we have a heading containing this exact string
        headings = get_all_nodes_with_tag(@doc, ["h1", "h2"])
        trimmed_title = cur_title.strip
        match = headings.any? { |heading| heading.text.strip == trimmed_title }

        # If we don't, extract the title out of the original title string
        unless match
          cur_title = orig_title[(orig_title.rindex(":") + 1)..]

          # If the title is now too short, try the first colon instead
          if word_count.call(cur_title) < 3
            cur_title = orig_title[(orig_title.index(":") + 1)..]
          # But if we have too many words before the colon there's something weird
          elsif word_count.call(orig_title[0, orig_title.index(":")]) > 5
            cur_title = orig_title
          end
        end
      elsif cur_title.length > 150 || cur_title.length < 15
        h_ones = @doc.css("h1")

        if h_ones.length == 1
          cur_title = get_inner_text(h_ones[0])
        end
      end

      cur_title = cur_title.strip.gsub(NORMALIZE, " ")

      # If we now have 4 words or fewer as our title, and either no
      # 'hierarchical' separators (\, /, > or ») were found in the original
      # title or we decreased the number of words by more than 1 word, use
      # the original title.
      cur_title_word_count = word_count.call(cur_title)
      if cur_title_word_count <= 4 &&
          (!title_had_hierarchical_separators ||
            cur_title_word_count !=
              word_count.call(orig_title.gsub(/\s[#{title_separators}]\s/, "")) - 1)
        cur_title = orig_title
      end

      cur_title
    end

    # Port of _getArticleMetadata (JS line 1783-1889)
    # Extracts metadata from <meta> tags and merges with JSON-LD data.
    def get_article_metadata(json_ld)
      metadata = {}
      values = {}

      meta_elements = @doc.css("meta")

      # property is a space-separated list of values
      property_pattern = /\s*(article|dc|dcterm|og|twitter)\s*:\s*(author|creator|description|published_time|title|site_name)\s*/i

      # name is a single value
      name_pattern = /\A\s*(?:(dc|dcterm|og|twitter|parsely|weibo:(article|webpage))\s*[-.:]\s*)?(author|creator|pub-date|description|title|site_name)\s*\z/i

      meta_elements.each do |element|
        element_name = element["name"]
        element_property = element["property"]
        content = element["content"]
        next unless content

        matches = nil
        name = nil

        if element_property
          matches = element_property.match(property_pattern)
          if matches
            # Convert to lowercase, and remove any whitespace
            name = matches[0].downcase.gsub(/\s/, "")
            values[name] = content.strip
          end
        end

        if !matches && element_name && name_pattern.match?(element_name)
          name = element_name
          if content
            # Convert to lowercase, remove whitespace, convert dots to colons
            name = name.downcase.gsub(/\s/, "").gsub(".", ":")
            values[name] = content.strip
          end
        end
      end

      # get title
      metadata["title"] =
        json_ld["title"] ||
        values["dc:title"] ||
        values["dcterm:title"] ||
        values["og:title"] ||
        values["weibo:article:title"] ||
        values["weibo:webpage:title"] ||
        values["title"] ||
        values["twitter:title"] ||
        values["parsely-title"]

      metadata["title"] ||= get_article_title

      article_author =
        if values["article:author"].is_a?(String) && !is_url?(values["article:author"])
          values["article:author"]
        end

      # get author
      metadata["byline"] =
        json_ld["byline"] ||
        values["dc:creator"] ||
        values["dcterm:creator"] ||
        values["author"] ||
        values["parsely-author"] ||
        article_author

      # get description
      metadata["excerpt"] =
        json_ld["excerpt"] ||
        values["dc:description"] ||
        values["dcterm:description"] ||
        values["og:description"] ||
        values["weibo:article:description"] ||
        values["weibo:webpage:description"] ||
        values["description"] ||
        values["twitter:description"]

      # get site name
      metadata["siteName"] = json_ld["site_name"] || values["og:site_name"]

      # get article published time
      metadata["publishedTime"] =
        json_ld["date_published"] ||
        values["article:published_time"] ||
        values["parsely-pub-date"] ||
        nil

      # Unescape HTML entities in all metadata values
      metadata["title"] = unescape_html_entities(metadata["title"])
      metadata["byline"] = unescape_html_entities(metadata["byline"])
      metadata["excerpt"] = unescape_html_entities(metadata["excerpt"])
      metadata["siteName"] = unescape_html_entities(metadata["siteName"])
      metadata["publishedTime"] = unescape_html_entities(metadata["publishedTime"])

      metadata
    end
  end
end
