# frozen_string_literal: true

module Readability
  module Cleaner
    private

    # Port of _setNodeTag (JS line 762)
    # In Nokogiri, we can mutate the tag name in place.
    def set_node_tag(node, tag)
      node.name = tag.downcase
      node
    end

    # Port of _prepDocument (JS line 669)
    def prep_document
      # Remove all style tags
      remove_nodes(get_all_nodes_with_tag(@doc, ["style"]))

      # Remove HTML comments — they interfere with phrasing content wrapping
      # and are not present in the JS test expected output
      @doc.traverse { |node| node.unlink if node.comment? }

      body = @doc.at_css("body")
      replace_brs(body) if body

      replace_node_tags(get_all_nodes_with_tag(@doc, ["font"]), "span")
    end

    # Port of _replaceBrs (JS line 706)
    # Replace 2+ consecutive <br> elements with a <p>, collecting
    # following phrasing content as children.
    def replace_brs(elem)
      get_all_nodes_with_tag(elem, ["br"]).each do |br|
        next_sib = br.next_sibling

        # Whether 2 or more <br> elements have been found and replaced with a <p>
        replaced = false

        # If we find a <br> chain, remove the <br>s until we hit another node
        # or non-whitespace. This leaves behind the first <br> in the chain.
        nxt = next_node(next_sib)
        while nxt && nxt.name == "br"
          replaced = true
          br_sibling = nxt.next_sibling
          nxt.unlink
          nxt = next_node(br_sibling)
        end

        # If we removed a <br> chain, replace the remaining <br> with a <p>.
        if replaced
          p_node = Nokogiri::XML::Node.new("p", @doc)
          br.replace(p_node)

          nxt = p_node.next_sibling
          while nxt
            # If we've hit another <br><br>, we're done adding children to this <p>.
            if nxt.name == "br"
              next_elem = next_node(nxt.next_sibling)
              if next_elem && next_elem.name == "br"
                break
              end
            end

            break unless is_phrasing_content?(nxt)

            # Otherwise, make this node a child of the new <p>.
            sibling = nxt.next_sibling
            p_node.add_child(nxt)
            nxt = sibling
          end

          # Trim trailing whitespace nodes from <p>
          while p_node.children.last && is_whitespace?(p_node.children.last)
            p_node.children.last.unlink
          end

          if p_node.parent && p_node.parent.name == "p"
            set_node_tag(p_node.parent, "div")
          end
        end
      end
    end

    # Port of _removeScripts (JS line 2001)
    def remove_scripts(doc)
      remove_nodes(get_all_nodes_with_tag(doc, ["script", "noscript"]))
    end

    # Port of _unwrapNoscriptImages (JS line 1918-1993)
    def unwrap_noscript_images(doc)
      # First pass: remove <img> elements without meaningful src/srcset/data-src/data-srcset
      # and no attribute value matching image extensions.
      imgs = doc.css("img").to_a
      imgs.each do |img|
        has_source = false
        img.attributes.each_value do |attr|
          case attr.name
          when "src", "srcset", "data-src", "data-srcset"
            has_source = true
            break
          end

          if /\.(jpg|jpeg|png|webp)/i.match?(attr.value)
            has_source = true
            break
          end
        end

        img.unlink unless has_source
      end

      # Second pass: for each <noscript> that contains a single image,
      # if its previous sibling is also a single image, replace it.
      noscripts = doc.css("noscript").to_a
      noscripts.each do |noscript|
        next unless is_single_image?(noscript)

        tmp = Nokogiri::HTML::DocumentFragment.parse(noscript.inner_html)

        prev_element = noscript.previous_element
        next unless prev_element && is_single_image?(prev_element)

        prev_img = prev_element
        prev_img = prev_element.at_css("img") unless prev_img.name == "img"

        new_img = tmp.at_css("img")
        next unless new_img

        prev_img.attributes.each_value do |attr|
          next if attr.value.empty?

          if attr.name == "src" || attr.name == "srcset" || /\.(jpg|jpeg|png|webp)/i.match?(attr.value)
            next if new_img[attr.name] == attr.value

            attr_name = attr.name
            if new_img[attr_name]
              attr_name = "data-old-#{attr_name}"
            end

            new_img[attr_name] = attr.value
          end
        end

        prev_element.replace(tmp.element_children.first)
      end
    end

    # Port of _prepArticle (JS line 792)
    def prep_article(article_content)
      clean_styles(article_content)

      # Check for data tables before we continue
      mark_data_tables(article_content)

      fix_lazy_images(article_content)

      # Clean out junk from the article content
      clean_conditionally(article_content, "form")
      clean_conditionally(article_content, "fieldset")
      clean(article_content, "object")
      clean(article_content, "embed")
      clean(article_content, "footer")
      clean(article_content, "link")
      clean(article_content, "aside")

      # Clean out elements with little content that have "share" in
      # their id/class combinations from final top candidates
      share_element_threshold = DEFAULT_CHAR_THRESHOLD

      article_content.element_children.each do |top_candidate|
        clean_matched_nodes(top_candidate) do |node, match_string|
          SHARE_ELEMENTS.match?(match_string) &&
            node.text.length < share_element_threshold
        end
      end

      clean(article_content, "iframe")
      clean(article_content, "input")
      clean(article_content, "textarea")
      clean(article_content, "select")
      clean(article_content, "button")
      clean_headers(article_content)

      # Do these last as the previous stuff may have removed junk
      # that will affect these
      clean_conditionally(article_content, "table")
      clean_conditionally(article_content, "ul")
      clean_conditionally(article_content, "div")

      # Replace H1 with H2 as H1 should be only title that is displayed separately
      replace_node_tags(get_all_nodes_with_tag(article_content, ["h1"]), "h2")

      # Remove extra paragraphs
      remove_nodes(get_all_nodes_with_tag(article_content, ["p"])) do |paragraph|
        content_element_count = get_all_nodes_with_tag(paragraph, ["img", "embed", "object", "iframe"]).length
        content_element_count == 0 && get_inner_text(paragraph, false).empty?
      end

      # Remove br before p
      get_all_nodes_with_tag(article_content, ["br"]).each do |br|
        nxt = next_node(br.next_sibling)
        br.unlink if nxt && nxt.name == "p"
      end

      # Remove single-cell tables
      get_all_nodes_with_tag(article_content, ["table"]).to_a.each do |table|
        tbody = has_single_tag_inside_element?(table, "tbody") ? table.element_children.first : table
        if has_single_tag_inside_element?(tbody, "tr")
          row = tbody.element_children.first
          if has_single_tag_inside_element?(row, "td")
            cell = row.element_children.first
            new_tag = cell.children.all? { |child| is_phrasing_content?(child) } ? "p" : "div"
            cell = set_node_tag(cell, new_tag)
            table.replace(cell)
          end
        end
      end
    end

    # Port of _cleanStyles (JS line 2114)
    def clean_styles(elem)
      return if !elem || elem.name == "svg"

      # Remove presentational attributes
      PRESENTATIONAL_ATTRIBUTES.each do |attr|
        elem.remove_attribute(attr)
      end

      if DEPRECATED_SIZE_ATTRIBUTE_ELEMS.include?(elem.name)
        elem.remove_attribute("width")
        elem.remove_attribute("height")
      end

      cur = elem.element_children.first
      while cur
        clean_styles(cur)
        cur = cur.next_element
      end
    end

    # Port of _markDataTables (JS line 2297-2354)
    def mark_data_tables(root)
      tables = root.css("table")
      tables.each do |table|
        role = table["role"]
        if role == "presentation"
          # NOT a data table
          next
        end

        datatable = table["datatable"]
        if datatable == "0"
          next
        end

        if table["summary"] && !table["summary"].empty?
          @data_tables.add(table)
          next
        end

        caption = table.at_css("caption")
        if caption && caption.children.length > 0
          @data_tables.add(table)
          next
        end

        # If the table has a descendant with any of these tags, consider a data table
        data_table_descendants = %w[col colgroup tfoot thead th]
        if data_table_descendants.any? { |tag| table.at_css(tag) }
          @data_tables.add(table)
          next
        end

        # Nested tables indicate a layout table
        if table.at_css("table")
          next
        end

        size_info = get_row_and_column_count(table)

        if size_info[:columns] == 1 || size_info[:rows] == 1
          next
        end

        if size_info[:rows] >= 10 || size_info[:columns] > 4
          @data_tables.add(table)
          next
        end

        # Now just go by size entirely
        @data_tables.add(table) if size_info[:rows] * size_info[:columns] > 10
      end
    end

    # Port of _getRowAndColumnCount (JS line 2266)
    def get_row_and_column_count(table)
      rows = 0
      columns = 0
      trs = table.css("tr")
      trs.each do |tr|
        rowspan = (tr["rowspan"] || 0).to_i
        rows += (rowspan > 0 ? rowspan : 1)

        columns_in_this_row = 0
        cells = tr.css("td")
        cells.each do |cell|
          colspan = (cell["colspan"] || 0).to_i
          columns_in_this_row += (colspan > 0 ? colspan : 1)
        end
        columns = [columns, columns_in_this_row].max
      end
      { rows: rows, columns: columns }
    end

    # Port of _fixLazyImages (JS line 2358)
    def fix_lazy_images(root)
      get_all_nodes_with_tag(root, ["img", "picture", "figure"]).each do |elem|
        src = elem["src"]

        # Check for base64 placeholder images
        if src && B64_DATA_URL.match?(src)
          parts = B64_DATA_URL.match(src)
          # Skip SVG - can have meaningful image in under 133 bytes
          next if parts[1] == "image/svg+xml"

          # Check if other attributes contain image references
          src_could_be_removed = false
          elem.attributes.each_value do |attr|
            next if attr.name == "src"

            if /\.(jpg|jpeg|png|webp)/i.match?(attr.value)
              src_could_be_removed = true
              break
            end
          end

          # If image is less than 133 bytes in base64 it's likely a placeholder
          if src_could_be_removed
            b64starts = parts[0].length
            b64length = src.length - b64starts
            elem.remove_attribute("src") if b64length < 133
          end
        end

        # Also check for "null" to work around jsdom issues.
        # Note: In JS, empty string is falsy, so `elem.src = ""` does NOT
        # prevent lazy-image processing. We must mirror that by treating
        # empty-string src/srcset the same as absent.
        elem_src = elem["src"]
        elem_srcset = elem["srcset"]
        if (elem_src && !elem_src.empty? || (elem_srcset && elem_srcset != "null" && !elem_srcset.empty?)) &&
            !(elem["class"] || "").downcase.include?("lazy")
          next
        end

        elem.attributes.each_value do |attr|
          next if %w[src srcset alt].include?(attr.name)

          copy_to = nil
          if /\.(jpg|jpeg|png|webp)\s+\d/.match?(attr.value)
            copy_to = "srcset"
          elsif /\A\s*\S+\.(jpg|jpeg|png|webp)\S*\s*\z/.match?(attr.value)
            copy_to = "src"
          end

          if copy_to
            if elem.name == "img" || elem.name == "picture"
              elem[copy_to] = attr.value
            elsif elem.name == "figure" && get_all_nodes_with_tag(elem, ["img", "picture"]).empty?
              img = Nokogiri::XML::Node.new("img", @doc)
              img[copy_to] = attr.value
              elem.add_child(img)
            end
          end
        end
      end
    end

    # Port of _clean (JS line 2208)
    def clean(elem, tag)
      is_embed = %w[object embed iframe].include?(tag)

      remove_nodes(get_all_nodes_with_tag(elem, [tag])) do |element|
        # Allow youtube and vimeo videos through
        if is_embed
          # Check attributes for allowed video URLs
          keep = false
          element.attributes.each_value do |attr|
            if @allowed_video_regex.match?(attr.value)
              keep = true
              break
            end
          end
          next false if keep

          # For embed with <object> tag, check inner HTML as well
          if element.name == "object" && @allowed_video_regex.match?(element.inner_html)
            next false
          end
        end

        true
      end
    end

    # Port of _cleanConditionally (JS line 2460-2657)
    def clean_conditionally(elem, tag)
      return unless flag_is_active?(FLAG_CLEAN_CONDITIONALLY)

      is_data_table = ->(t) { @data_tables.include?(t) }

      remove_nodes(get_all_nodes_with_tag(elem, [tag])) do |node|
        is_list = (tag == "ul" || tag == "ol")

        unless is_list
          list_length = 0
          get_all_nodes_with_tag(node, ["ul", "ol"]).each do |list|
            list_length += get_inner_text(list).length
          end
          node_text_length = get_inner_text(node).length
          is_list = node_text_length > 0 && list_length.to_f / node_text_length > 0.9
        end

        # First check if this node IS a data table
        if tag == "table" && is_data_table.call(node)
          next false
        end

        # Next check if we're inside a data table
        if has_ancestor_tag?(node, "table", -1, &is_data_table)
          next false
        end

        if has_ancestor_tag?(node, "code")
          next false
        end

        # Keep element if it contains a data table
        if node.css("table").any? { |tbl| @data_tables.include?(tbl) }
          next false
        end

        weight = get_class_weight(node)
        content_score = 0

        if weight + content_score < 0
          next true
        end

        if get_char_count(node, ",") < 10
          p_count = node.css("p").length
          img_count = node.css("img").length
          li_count = node.css("li").length - 100
          input_count = node.css("input").length
          heading_density = get_text_density(node, ["h1", "h2", "h3", "h4", "h5", "h6"])

          embed_count = 0
          embeds = get_all_nodes_with_tag(node, ["object", "embed", "iframe"])

          skip_removal = false
          embeds.each do |embed_node|
            # Check attributes for allowed video URLs
            embed_node.attributes.each_value do |attr|
              if @allowed_video_regex.match?(attr.value)
                skip_removal = true
                break
              end
            end
            break if skip_removal

            if embed_node.name == "object" && @allowed_video_regex.match?(embed_node.inner_html)
              skip_removal = true
              break
            end

            embed_count += 1
          end
          next false if skip_removal

          inner_text = get_inner_text(node)

          # Toss any node whose inner text contains nothing but suspicious words
          if AD_WORDS.match?(inner_text) || LOADING_WORDS.match?(inner_text)
            next true
          end

          content_length = inner_text.length
          link_density = get_link_density(node)
          textish_tags = %w[span li td] + DIV_TO_P_ELEMS.to_a
          text_density = get_text_density(node, textish_tags)
          is_figure_child = has_ancestor_tag?(node, "figure")

          # Apply shadiness checks
          have_to_remove = false
          errs = []

          if !is_figure_child && img_count > 1 && p_count.to_f / img_count < 0.5
            errs << "Bad p to img ratio"
          end
          if !is_list && li_count > p_count
            errs << "Too many li's outside of a list"
          end
          if input_count > (p_count / 3).floor
            errs << "Too many inputs per p"
          end
          if !is_list && !is_figure_child && heading_density < 0.9 &&
              content_length < 25 && (img_count == 0 || img_count > 2) && link_density > 0
            errs << "Suspiciously short"
          end
          if !is_list && weight < 25 && link_density > 0.2 + @link_density_modifier
            errs << "Low weight and a little linky"
          end
          if weight >= 25 && link_density > 0.5 + @link_density_modifier
            errs << "High weight and mostly links"
          end
          if (embed_count == 1 && content_length < 75) || embed_count > 1
            errs << "Suspicious embed"
          end
          if img_count == 0 && text_density == 0
            errs << "No useful content"
          end

          have_to_remove = errs.any?

          # Allow simple lists of images to remain
          if is_list && have_to_remove
            all_single_child = true
            node.element_children.each do |child|
              if child.element_children.length > 1
                all_single_child = false
                break
              end
            end

            if all_single_child
              li_total = node.css("li").length
              have_to_remove = false if img_count == li_total
            end
          end

          next have_to_remove
        end

        false
      end
    end

    # Port of _cleanMatchedNodes (JS line 2667)
    def clean_matched_nodes(elem, &filter)
      end_of_search_marker = get_next_node(elem, true)
      nxt = get_next_node(elem)
      while nxt && nxt != end_of_search_marker
        match_string = "#{nxt["class"] || ""} #{nxt["id"] || ""}"
        if filter.call(nxt, match_string)
          nxt = remove_and_get_next(nxt)
        else
          nxt = get_next_node(nxt)
        end
      end
    end

    # Port of _cleanHeaders (JS line 2685)
    def clean_headers(elem)
      heading_nodes = get_all_nodes_with_tag(elem, ["h1", "h2"])
      remove_nodes(heading_nodes) do |node|
        get_class_weight(node) < 0
      end
    end

    # Port of _headerDuplicatesTitle (JS line 2703)
    def header_duplicates_title?(node)
      return false unless node.name == "h1" || node.name == "h2"

      heading = get_inner_text(node, false)
      text_similarity(@article_title || "", heading) > 0.75
    end

    # Port of _postProcessContent (JS line 282)
    def post_process_content(article_content)
      fix_relative_uris(article_content)
      simplify_nested_elements(article_content)

      clean_classes(article_content) unless @keep_classes
    end

    # Port of _fixRelativeUris (JS line 457-536)
    def fix_relative_uris(article_content)
      document_uri = @url
      return unless document_uri

      # Compute the effective base URI, considering <base> elements (like JS document.baseURI)
      base_uri = document_uri
      base_element = @doc.at_css("base[href]")
      if base_element
        base_href = base_element["href"]
        if base_href && !base_href.empty?
          begin
            base_uri = URI.join(document_uri, base_href).to_s
          rescue URI::InvalidURIError, URI::InvalidComponentError, URI::BadURIError
            # keep document_uri as base
          end
        end
      end

      to_absolute_uri = lambda do |uri|
        # Strip whitespace — Nokogiri preserves newlines in attributes,
        # but JS DOM normalizes them
        uri = uri.strip

        # Leave hash links alone if base URI matches document URI
        return uri if base_uri == document_uri && uri.start_with?("#")

        # Quick check for non-HTTP scheme URIs before parsing — return as-is
        # (with file: URL normalization for Windows drive letters)
        if uri.match?(/\A[a-z][a-z0-9+\-.]*:/i) && !uri.match?(/\Ahttps?:/i)
          # Normalize Windows drive letters in file: URIs (C| -> C:) per WHATWG URL spec
          if uri.match?(/\Afile:/i)
            return uri.sub(%r{\A(file:///[A-Za-z])\|(/)}i, '\1:\2')
          end
          return uri
        end

        begin
          resolved = URI.join(base_uri, uri)
          # Match JS URL normalization
          if resolved.is_a?(URI::HTTP)
            # Add trailing slash for scheme-based URLs with empty path
            if resolved.path.nil? || resolved.path.empty?
              resolved.path = "/"
            end
            # Lowercase hostname (JS new URL() does this per WHATWG URL spec)
            resolved.host = resolved.host.downcase if resolved.host
          end
          resolved.to_s
        rescue URI::InvalidURIError, URI::InvalidComponentError, URI::BadURIError
          # URI.join failed — try manual resolution as a relative path
          begin
            base = URI.parse(base_uri)
            # Remove filename from base path to get directory
            base_dir = base.path.sub(%r{/[^/]*\z}, "/")
            base.path = base_dir + uri
            base.to_s
          rescue
            uri
          end
        end
      end

      # Fix anchor tags
      get_all_nodes_with_tag(article_content, ["a"]).to_a.each do |link|
        href = link["href"]
        next unless href

        if href.strip.start_with?("javascript:")
          # Replace javascript: links
          if link.children.length == 1 && link.children[0].text?
            text_node = Nokogiri::XML::Text.new(link.text, @doc)
            link.replace(text_node)
          else
            container = Nokogiri::XML::Node.new("span", @doc)
            while link.children.first
              container.add_child(link.children.first)
            end
            link.replace(container)
          end
        else
          link["href"] = to_absolute_uri.call(href)
        end
      end

      # Fix media tags
      media_tags = %w[img picture figure video audio source]
      get_all_nodes_with_tag(article_content, media_tags).each do |media|
        src = media["src"]
        poster = media["poster"]
        srcset = media["srcset"]

        media["src"] = to_absolute_uri.call(src) if src
        media["poster"] = to_absolute_uri.call(poster) if poster

        if srcset
          new_srcset = srcset.gsub(SRCSET_URL) do
            p1 = Regexp.last_match(1)
            p2 = Regexp.last_match(2) || ""
            p3 = Regexp.last_match(3)
            "#{to_absolute_uri.call(p1)}#{p2}#{p3}"
          end
          media["srcset"] = new_srcset
        end
      end
    end

    # Port of _simplifyNestedElements (JS line 538-566)
    def simplify_nested_elements(article_content)
      node = article_content

      while node
        if node.parent &&
            %w[div section].include?(node.name) &&
            !(node["id"] && node["id"].start_with?("readability"))

          if is_element_without_content?(node)
            node = remove_and_get_next(node)
            next
          elsif has_single_tag_inside_element?(node, "div") ||
                has_single_tag_inside_element?(node, "section")
            child = node.element_children[0]
            # Copy attributes from parent to child
            node.attributes.each_value do |attr|
              child[attr.name] = attr.value
            end
            node.replace(child)
            node = child
            next
          end
        end

        node = get_next_node(node)
      end
    end

    # Port of _cleanClasses (JS line 418)
    def clean_classes(node)
      class_name = (node["class"] || "")
        .split(/\s+/)
        .select { |cls| @classes_to_preserve.include?(cls) }
        .join(" ")

      if class_name.empty?
        node.remove_attribute("class")
      else
        node["class"] = class_name
      end

      child = node.element_children.first
      while child
        clean_classes(child)
        child = child.next_element
      end
    end
  end
end
