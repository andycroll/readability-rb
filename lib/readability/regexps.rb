# frozen_string_literal: true

require "set"

module Readability
  # All regex patterns from Readability.js REGEXPS object
  # NOTE: All tag name constants are LOWERCASE (Nokogiri convention)

  # Flags
  FLAG_STRIP_UNLIKELYS = 0x1
  FLAG_WEIGHT_CLASSES = 0x2
  FLAG_CLEAN_CONDITIONALLY = 0x4

  # Defaults
  DEFAULT_MAX_ELEMS_TO_PARSE = 0
  DEFAULT_N_TOP_CANDIDATES = 5
  DEFAULT_CHAR_THRESHOLD = 500

  DEFAULT_TAGS_TO_SCORE = %w[section h2 h3 h4 h5 h6 p td pre].freeze

  # Regexps — ported from the JS REGEXPS object
  UNLIKELY_CANDIDATES = /-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote/i

  OK_MAYBE_CANDIDATE = /and|article|body|column|content|main|mathjax|shadow/i

  POSITIVE = /article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story/i

  NEGATIVE = /-ad-|hidden|\Ahid\z| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget/i

  EXTRANEOUS = /print|archive|comment|discuss|e[\-]?mail|share|reply|all|login|sign|single|utility/i

  BYLINE = /byline|author|dateline|writtenby|p-author/i

  REPLACE_FONTS = /<(\/?)font[^>]*>/i

  NORMALIZE = /\s{2,}/

  VIDEOS = /\/\/(www\.)?((dailymotion|youtube|youtube-nocookie|player\.vimeo|v\.qq|bilibili|live.bilibili)\.com|(archive|upload\.wikimedia)\.org|player\.twitch\.tv)/i

  SHARE_ELEMENTS = /(\b|_)(share|sharedaddy)(\b|_)/i

  NEXT_LINK = /(next|weiter|continue|>([^\|]|$)|»([^\|]|$))/i

  PREV_LINK = /(prev|earl|old|new|<|«)/i

  TOKENIZE = /\W+/

  WHITESPACE = /\A\s*\z/

  HAS_CONTENT = /\S\z/

  HASH_URL = /\A#.+/

  SRCSET_URL = /(\S+)(\s+[\d.]+[xw])?(\s*(?:,|$))/

  B64_DATA_URL = /\Adata:\s*([^\s;,]+)\s*;\s*base64\s*,/i

  # Commas as used in Latin, Sindhi, Chinese and various other scripts.
  # see: https://en.wikipedia.org/wiki/Comma#Comma_variants
  COMMAS = /\u{002C}|\u{060C}|\u{FE50}|\u{FE10}|\u{FE11}|\u{2E41}|\u{2E34}|\u{2E32}|\u{FF0C}/

  # See: https://schema.org/Article
  JSON_LD_ARTICLE_TYPES = /\A(Article|AdvertiserContentArticle|NewsArticle|AnalysisNewsArticle|AskPublicNewsArticle|BackgroundNewsArticle|OpinionNewsArticle|ReportageNewsArticle|ReviewNewsArticle|Report|SatiricalArticle|ScholarlyArticle|MedicalScholarlyArticle|SocialMediaPosting|BlogPosting|LiveBlogPosting|DiscussionForumPosting|TechArticle|APIReference)\z/

  AD_WORDS = /\A(ad(vertising|vertisement)?|pub(licité)?|werb(ung)?|广告|Реклама|Anuncio)\z/iu

  LOADING_WORDS = /\A((loading|正在加载|Загрузка|chargement|cargando)(…|\.\.\.)?)?\z/iu

  # Element/role lists — ALL LOWERCASE
  UNLIKELY_ROLES = %w[menu menubar complementary navigation alert alertdialog dialog].freeze

  DIV_TO_P_ELEMS = Set.new(%w[blockquote dl div img ol p pre table ul]).freeze

  ALTER_TO_DIV_EXCEPTIONS = %w[div article section p ol ul].freeze

  PRESENTATIONAL_ATTRIBUTES = %w[align background bgcolor border cellpadding cellspacing frame hspace rules style valign vspace].freeze

  DEPRECATED_SIZE_ATTRIBUTE_ELEMS = %w[table th td hr pre].freeze

  PHRASING_ELEMS = %w[abbr audio b bdo br button cite code data datalist dfn em embed i img input kbd label mark math meter noscript object output progress q ruby samp script select small span strong sub sup textarea time var wbr].freeze

  CLASSES_TO_PRESERVE = %w[page].freeze

  HTML_ESCAPE_MAP = {
    "lt" => "<",
    "gt" => ">",
    "amp" => "&",
    "quot" => '"',
    "apos" => "'",
  }.freeze
end
