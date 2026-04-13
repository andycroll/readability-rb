# frozen_string_literal: true

module Readability
  Result = Struct.new(
    :title,
    :byline,
    :dir,
    :lang,
    :content,
    :text_content,
    :length,
    :excerpt,
    :site_name,
    :published_time,
    keyword_init: true
  )
end
