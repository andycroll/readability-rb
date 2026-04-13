# frozen_string_literal: true

require "set"

module Readability
  class Document
    include Utils
    include Scoring
    include Metadata
    include Cleaner

    def initialize(doc, url: nil, **options)
      @doc = doc.dup  # Deep clone
      @url = url
      @article_title = nil
      @article_byline = nil
      @article_dir = nil
      @article_site_name = nil
      @article_lang = nil
      @attempts = []
      @metadata = {}
      @candidates = {}
      @data_tables = Set.new

      # Options — from JS constructor lines 49-66
      @debug = !!options[:debug]
      @max_elems_to_parse = options[:max_elems_to_parse] || DEFAULT_MAX_ELEMS_TO_PARSE
      @nb_top_candidates = options[:nb_top_candidates] || DEFAULT_N_TOP_CANDIDATES
      @char_threshold = options[:char_threshold] || DEFAULT_CHAR_THRESHOLD
      @classes_to_preserve = CLASSES_TO_PRESERVE + (options[:classes_to_preserve] || [])
      @keep_classes = !!options[:keep_classes]
      @serializer = options[:serializer] || ->(el) { el.inner_html }
      @disable_json_ld = !!options[:disable_json_ld]
      @allowed_video_regex = options[:allowed_video_regex] || VIDEOS
      @link_density_modifier = options[:link_density_modifier] || 0

      # Flags — all active initially
      @flags = FLAG_STRIP_UNLIKELYS | FLAG_WEIGHT_CLASSES | FLAG_CLEAN_CONDITIONALLY
    end

    # Port of parse() — JS lines 2747-2805
    def parse
      # Avoid parsing too large documents
      if @max_elems_to_parse > 0
        count = 0
        @doc.traverse do |n|
          if n.element?
            count += 1
            if count > @max_elems_to_parse
              raise "Aborting parsing document; #{count} elements found"
            end
          end
        end
      end

      # Unwrap image from noscript
      unwrap_noscript_images(@doc)

      # Extract JSON-LD metadata before removing scripts
      json_ld = @disable_json_ld ? {} : get_json_ld(@doc)

      # Remove script tags from the document
      remove_scripts(@doc)

      prep_document

      # Cache the prepped body HTML for retry re-parsing (avoids innerHTML= cost)
      @prepped_body_html = @doc.at_css("body")&.inner_html

      metadata = get_article_metadata(json_ld)
      @metadata = metadata
      @article_title = metadata["title"]

      article_content = grab_article
      return nil unless article_content

      log("Grabbed: #{article_content.inner_html}")

      post_process_content(article_content)

      # If we haven't found an excerpt in the article's metadata, use the article's
      # first paragraph as the excerpt.
      if !metadata["excerpt"] || metadata["excerpt"].empty?
        paragraphs = article_content.css("p")
        if paragraphs.length > 0
          metadata["excerpt"] = paragraphs[0].text.strip
        end
      end

      text_content = article_content.text

      Result.new(
        title: @article_title,
        byline: (metadata["byline"] && !metadata["byline"].empty? ? metadata["byline"] : nil) || @article_byline,
        dir: @article_dir,
        lang: @article_lang,
        content: @serializer.call(article_content),
        text_content: text_content,
        length: text_content.length,
        excerpt: metadata["excerpt"],
        site_name: metadata["siteName"] || @article_site_name,
        published_time: metadata["publishedTime"]
      )
    end

    private

    # Port of _grabArticle() — JS lines 1041-1623
    def grab_article(page = nil)
      log("**** grabArticle ****")
      is_paging = !page.nil?
      page = page || @doc.at_css("body")

      # We can't grab an article if we don't have a page!
      unless page
        log("No body found in document. Abort.")
        return nil
      end

      # Preserve the lang attribute from the HTML element before any retry re-parsing
      preserved_article_lang = @doc.root && @doc.root["lang"]
      preserved_article_dir = @doc.root && @doc.root["dir"]

      while true
        log("Starting grabArticle loop")
        strip_unlikely_candidates = flag_is_active?(FLAG_STRIP_UNLIKELYS)

        # Reset candidates and data tables for each iteration
        @candidates = {}
        @data_tables = Set.new

        # First, node prepping. Trash nodes that look cruddy and turn divs
        # into P tags where they have been used inappropriately.
        elements_to_score = []
        node = @doc.root

        should_remove_title_header = true

        while node
          if node.name == "html"
            @article_lang = node["lang"]
          end

          match_string = "#{node["class"]} #{node["id"]}"

          unless is_probably_visible?(node)
            log("Removing hidden node - #{match_string}")
            node = remove_and_get_next(node)
            next
          end

          # User is not able to see elements applied with both "aria-modal = true" and "role = dialog"
          if node["aria-modal"] == "true" && node["role"] == "dialog"
            node = remove_and_get_next(node)
            next
          end

          # Check for byline
          if !@article_byline && (@metadata["byline"].nil? || @metadata["byline"].empty?) && is_valid_byline?(node, match_string)
            # Find child node matching [itemprop="name"] for more accurate author name
            end_of_search_marker_node = get_next_node(node, true)
            nxt = get_next_node(node)
            item_prop_name_node = nil
            while nxt && nxt != end_of_search_marker_node
              itemprop = nxt["itemprop"]
              if itemprop && itemprop.include?("name")
                item_prop_name_node = nxt
                break
              else
                nxt = get_next_node(nxt)
              end
            end
            @article_byline = (item_prop_name_node || node).text.strip
            node = remove_and_get_next(node)
            next
          end

          if should_remove_title_header && header_duplicates_title?(node)
            log("Removing header: ", node.text.strip, (@article_title || "").strip)
            should_remove_title_header = false
            node = remove_and_get_next(node)
            next
          end

          # Remove unlikely candidates
          if strip_unlikely_candidates
            if UNLIKELY_CANDIDATES.match?(match_string) &&
                !OK_MAYBE_CANDIDATE.match?(match_string) &&
                !has_ancestor_tag?(node, "table") &&
                !has_ancestor_tag?(node, "code") &&
                node.name != "body" &&
                node.name != "a"
              log("Removing unlikely candidate - #{match_string}")
              node = remove_and_get_next(node)
              next
            end

            if UNLIKELY_ROLES.include?(node["role"])
              log("Removing content with role #{node["role"]} - #{match_string}")
              node = remove_and_get_next(node)
              next
            end
          end

          # Remove DIV, SECTION, and HEADER nodes without any content
          if %w[div section header h1 h2 h3 h4 h5 h6].include?(node.name) &&
              is_element_without_content?(node)
            node = remove_and_get_next(node)
            next
          end

          if DEFAULT_TAGS_TO_SCORE.include?(node.name)
            elements_to_score << node
          end

          # Turn all divs that don't have children block level elements into p's
          if node.name == "div"
            # Put phrasing content into paragraphs.
            child_node = node.children.first
            while child_node
              next_sibling = child_node.next_sibling
              if is_phrasing_content?(child_node)
                fragment = Nokogiri::HTML::DocumentFragment.new(@doc)
                # Collect all consecutive phrasing content into a fragment.
                loop do
                  next_sibling = child_node.next_sibling
                  fragment.add_child(child_node)
                  child_node = next_sibling
                  break unless child_node && is_phrasing_content?(child_node)
                end

                # Trim leading whitespace from the fragment.
                while fragment.children.first && is_whitespace?(fragment.children.first)
                  fragment.children.first.unlink
                end
                # Trim trailing whitespace from the fragment.
                while fragment.children.last && is_whitespace?(fragment.children.last)
                  fragment.children.last.unlink
                end

                # If the fragment contains anything, wrap it in a paragraph and
                # insert it before the next non-phrasing node.
                if fragment.children.first
                  p_node = Nokogiri::XML::Node.new("p", @doc)
                  p_node.add_child(fragment)
                  if next_sibling
                    next_sibling.add_previous_sibling(p_node)
                  else
                    node.add_child(p_node)
                  end
                end
              end
              child_node = next_sibling
            end

            # Sites like http://mobile.slate.com enclose each paragraph with a DIV
            # element. DIVs with only a P element inside and no text content can be
            # safely converted into plain P elements.
            if has_single_tag_inside_element?(node, "p") && get_link_density(node) < 0.25
              new_node = node.element_children[0]
              node.replace(new_node)
              node = new_node
              elements_to_score << node
            elsif !has_child_block_element?(node)
              node = set_node_tag(node, "p")
              elements_to_score << node
            end
          end
          node = get_next_node(node)
        end

        # Loop through all paragraphs, and assign a score to them based on how
        # content-y they look. Then add their score to their parent node.
        candidates = []
        elements_to_score.each do |element_to_score|
          parent = element_to_score.parent
          next if !parent || !parent.element?

          # If this paragraph is less than 25 characters, don't even count it.
          inner_text = get_inner_text(element_to_score)
          next if inner_text.length < 25

          # Exclude nodes with no ancestor.
          ancestors = get_node_ancestors(element_to_score, 5)
          next if ancestors.empty?

          content_score = 0

          # Add a point for the paragraph itself as a base.
          content_score += 1

          # Add points for any commas within this paragraph.
          content_score += inner_text.split(COMMAS).length

          # For every 100 characters in this paragraph, add another point. Up to 3 points.
          content_score += [inner_text.length / 100, 3].min

          # Initialize and score ancestors.
          ancestors.each_with_index do |ancestor, level|
            next if !ancestor.element? || !ancestor.parent || !ancestor.parent.element?

            unless @candidates.key?(ancestor)
              initialize_node(ancestor)
              candidates << ancestor
            end

            # Node score divider:
            # - parent:             1 (no division)
            # - grandparent:        2
            # - great grandparent+: ancestor level * 3
            if level == 0
              score_divider = 1
            elsif level == 1
              score_divider = 2
            else
              score_divider = level * 3
            end
            @candidates[ancestor][:content_score] += content_score.to_f / score_divider
          end
        end

        # After we've calculated scores, loop through all of the possible
        # candidate nodes we found and find the one with the highest score.
        top_candidates = []
        candidates.each do |candidate|
          # Scale the final candidates score based on link density.
          candidate_score = content_score(candidate) * (1 - get_link_density(candidate))
          set_content_score(candidate, candidate_score)

          log("Candidate:", candidate, "with score #{candidate_score}")

          (0...@nb_top_candidates).each do |t|
            a_top_candidate = top_candidates[t]

            if !a_top_candidate || candidate_score > content_score(a_top_candidate)
              top_candidates.insert(t, candidate)
              top_candidates.pop if top_candidates.length > @nb_top_candidates
              break
            end
          end
        end

        top_candidate = top_candidates[0]
        needed_to_create_top_candidate = false
        parent_of_top_candidate = nil

        # If we still have no top candidate, just use the body as a last resort.
        if top_candidate.nil? || top_candidate.name == "body"
          # Move all of the page's children into topCandidate
          top_candidate = Nokogiri::XML::Node.new("div", @doc)
          needed_to_create_top_candidate = true
          # Move everything (not just elements, also text nodes etc.) into the container
          while page.children.first
            log("Moving child out:", page.children.first)
            top_candidate.add_child(page.children.first)
          end

          page.add_child(top_candidate)
          initialize_node(top_candidate)
        else
          # Find a better top candidate node if it contains (at least three) nodes
          # which belong to topCandidates array and whose scores are quite close.
          alternative_candidate_ancestors = []
          (1...top_candidates.length).each do |i|
            if content_score(top_candidates[i]).to_f / content_score(top_candidate) >= 0.75
              alternative_candidate_ancestors << get_node_ancestors(top_candidates[i])
            end
          end
          minimum_topcandidates = 3
          if alternative_candidate_ancestors.length >= minimum_topcandidates
            parent_of_top_candidate = top_candidate.parent
            while parent_of_top_candidate.name != "body"
              lists_containing_this_ancestor = 0
              alternative_candidate_ancestors.each do |ancestor_list|
                break if lists_containing_this_ancestor >= minimum_topcandidates
                lists_containing_this_ancestor += 1 if ancestor_list.include?(parent_of_top_candidate)
              end
              if lists_containing_this_ancestor >= minimum_topcandidates
                top_candidate = parent_of_top_candidate
                break
              end
              parent_of_top_candidate = parent_of_top_candidate.parent
            end
          end

          initialize_node(top_candidate) unless @candidates.key?(top_candidate)

          # Walk up tree if parent score is increasing
          parent_of_top_candidate = top_candidate.parent
          last_score = content_score(top_candidate)
          score_threshold = last_score / 3.0
          while parent_of_top_candidate.name != "body"
            unless @candidates.key?(parent_of_top_candidate)
              parent_of_top_candidate = parent_of_top_candidate.parent
              next
            end
            parent_score = content_score(parent_of_top_candidate)
            break if parent_score < score_threshold

            if parent_score > last_score
              # Alright! We found a better parent to use.
              top_candidate = parent_of_top_candidate
              break
            end
            last_score = content_score(parent_of_top_candidate)
            parent_of_top_candidate = parent_of_top_candidate.parent
          end

          # If the top candidate is the only child, use parent instead.
          parent_of_top_candidate = top_candidate.parent
          while parent_of_top_candidate.name != "body" &&
              parent_of_top_candidate.element_children.length == 1
            top_candidate = parent_of_top_candidate
            parent_of_top_candidate = top_candidate.parent
          end
          initialize_node(top_candidate) unless @candidates.key?(top_candidate)
        end

        # Now that we have the top candidate, look through its siblings for content
        # that might also be related.
        article_content = Nokogiri::XML::Node.new("div", @doc)
        article_content["id"] = "readability-content" if is_paging

        sibling_score_threshold = [10, content_score(top_candidate) * 0.2].max

        # Keep potential top candidate's parent node to try to get text direction later.
        parent_of_top_candidate = top_candidate.parent
        siblings = parent_of_top_candidate.element_children.to_a

        siblings.each do |sibling|
          # Skip already-moved nodes
          next unless sibling.parent

          append = false

          log("Looking at sibling node:", sibling,
            @candidates.key?(sibling) ? "with score #{content_score(sibling)}" : "")
          log("Sibling has score",
            @candidates.key?(sibling) ? content_score(sibling) : "Unknown")

          if sibling == top_candidate
            append = true
          else
            content_bonus = 0

            # Give a bonus if sibling nodes and top candidates have the same classname
            sibling_class = sibling["class"] || ""
            top_class = top_candidate["class"] || ""
            if sibling_class == top_class && !top_class.empty?
              content_bonus += content_score(top_candidate) * 0.2
            end

            if @candidates.key?(sibling) &&
                content_score(sibling) + content_bonus >= sibling_score_threshold
              append = true
            elsif sibling.name == "p"
              link_density = get_link_density(sibling)
              node_content = get_inner_text(sibling)
              node_length = node_content.length

              if node_length > 80 && link_density < 0.25
                append = true
              elsif node_length < 80 && node_length > 0 && link_density == 0 &&
                  node_content.match?(/\.( |$)/)
                append = true
              end
            end
          end

          if append
            log("Appending node:", sibling)

            unless ALTER_TO_DIV_EXCEPTIONS.include?(sibling.name)
              log("Altering sibling:", sibling, "to div.")
              sibling = set_node_tag(sibling, "div")
            end

            article_content.add_child(sibling)
          end
        end

        log("Article content pre-prep: #{article_content.inner_html}") if @debug
        # So we have all of the content that we need. Now we clean it up for presentation.
        prep_article(article_content)
        log("Article content post-prep: #{article_content.inner_html}") if @debug

        if needed_to_create_top_candidate
          # We already created a fake div thing, and there wouldn't have been any siblings left
          # for the previous loop, so there's no point trying to create a new div.
          top_candidate["id"] = "readability-page-1"
          top_candidate["class"] = "page"
        else
          div = Nokogiri::XML::Node.new("div", @doc)
          div["id"] = "readability-page-1"
          div["class"] = "page"
          while article_content.children.first
            div.add_child(article_content.children.first)
          end
          article_content.add_child(div)
        end

        log("Article content after paging: #{article_content.inner_html}") if @debug

        parse_successful = true

        # Check to see if we got any meaningful content.
        text_length = get_inner_text(article_content, true).length
        if text_length < @char_threshold
          parse_successful = false

          # Store serialized HTML instead of node references to avoid pinning old documents
          @attempts << {
            html: article_content.inner_html,
            text_length: text_length
          }

          if flag_is_active?(FLAG_STRIP_UNLIKELYS)
            remove_flag(FLAG_STRIP_UNLIKELYS)
          elsif flag_is_active?(FLAG_WEIGHT_CLASSES)
            remove_flag(FLAG_WEIGHT_CLASSES)
          elsif flag_is_active?(FLAG_CLEAN_CONDITIONALLY)
            remove_flag(FLAG_CLEAN_CONDITIONALLY)
          else
            # No luck after removing flags, just return the longest text we found
            @attempts.sort_by! { |a| -a[:text_length] }

            # But first check if we actually have something
            return nil if @attempts[0][:text_length] == 0

            # Re-parse the best attempt from serialized HTML
            best_doc = Nokogiri::HTML5("<html><body>#{@attempts[0][:html]}</body></html>")
            best_doc.root["lang"] = preserved_article_lang if preserved_article_lang
            best_doc.root["dir"] = preserved_article_dir if preserved_article_dir
            article_content = best_doc.at_css("body")
            @doc = best_doc
            parse_successful = true
          end

          unless parse_successful
            # Create a fresh document from the prepped body HTML, allowing the old one to be GC'd
            @doc = Nokogiri::HTML5("<html><head></head><body>#{@prepped_body_html}</body></html>")
            # Restore the lang attribute on the new HTML element so it's picked up during traversal
            @doc.root["lang"] = preserved_article_lang if preserved_article_lang
            @doc.root["dir"] = preserved_article_dir if preserved_article_dir
            page = @doc.at_css("body")

            # Clear node-referencing instance variables since they point to the old document
            @candidates = {}
            @data_tables = Set.new
            @article_byline = nil
            @article_dir = nil
            @article_lang = preserved_article_lang
          end
        end

        if parse_successful
          # Find out text direction from ancestors of final top candidate.
          ancestors = [parent_of_top_candidate, top_candidate] +
            get_node_ancestors(parent_of_top_candidate)
          ancestors.each do |ancestor|
            next unless ancestor.element?
            article_dir = ancestor["dir"]
            if article_dir
              @article_dir = article_dir
              break
            end
          end
          return article_content
        end
      end
    end

    def flag_is_active?(flag)
      (@flags & flag) > 0
    end

    def remove_flag(flag)
      @flags = @flags & ~flag
    end

    def log(*args)
      return unless @debug
      puts "Reader: (Readability) #{args.map(&:to_s).join(' ')}"
    end
  end
end
