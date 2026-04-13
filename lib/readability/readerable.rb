# frozen_string_literal: true

require "set"

module Readability
  module Readerable
    module_function

    # For backward compat: accept a proc as second positional argument (matches JS API)
    def probably_readerable?(doc, options_or_checker = {}, **kwargs)
      if options_or_checker.is_a?(Proc)
        kwargs[:visibility_checker] = options_or_checker
        options_or_checker = {}
      end
      options = options_or_checker.is_a?(Hash) ? options_or_checker.merge(kwargs) : kwargs

      min_score = options.fetch(:min_score, 20)
      min_content_length = options.fetch(:min_content_length, 140)
      visibility_checker = options.fetch(:visibility_checker, nil)
      visibility_checker ||= method(:node_visible?)

      nodes = doc.css("p, pre, article")

      # Also include div parents of br nodes (some articles use div > br structure)
      br_nodes = doc.css("div > br")
      if br_nodes.any?
        node_set = Set.new(nodes.to_a)
        br_nodes.each { |br| node_set.add(br.parent) }
        nodes = node_set.to_a
      end

      score = 0.0
      nodes.any? do |node|
        next false unless visibility_checker.call(node)

        match_string = "#{node['class']} #{node['id']}"
        next false if UNLIKELY_CANDIDATES.match?(match_string) && !OK_MAYBE_CANDIDATE.match?(match_string)
        next false if node.matches?("li p")

        text_length = node.text.strip.length
        next false if text_length < min_content_length

        score += Math.sqrt(text_length - min_content_length)
        score > min_score
      end
    end

    # NOTE: This matches JS isNodeVisible exactly — does NOT check visibility:hidden
    def node_visible?(node)
      style = node['style']
      return false if style && style =~ /display:\s*none/i
      return false if !node['hidden'].nil?
      aria_hidden = node['aria-hidden']
      if aria_hidden == "true"
        class_name = node['class'] || ""
        return false unless class_name.include?("fallback-image")
      end
      true
    end
  end
end
