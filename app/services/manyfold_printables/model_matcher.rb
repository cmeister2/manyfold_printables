# frozen_string_literal: true

module ManyfoldPrintables
  # Ranks public search results against a local model title. A bounded
  # shortlist receives token edit-distance comparisons; linking remains
  # an explicit choice made by the user.
  class ModelMatcher
    MAX_ITEMS = 20_000
    MAX_ITEM_BYTES = 512
    MAX_QUERY_BYTES = 2048
    MAX_TOKENS = 64
    MAX_TOKEN_CHARS = 64
    MAX_FUZZY_WORDS = 12
    MAX_CANDIDATES = 100
    MAX_RESULTS = 20
    STOP_WORDS = %w[a an and for of the to].freeze
    FILE_SUFFIXES = %w[supported supports unsupported presupported hollow solid files file final mesh stl obj zip lys chitubox lychee].freeze
    EXTENSION = /\.(?:stl|3mf|obj|ply|off|amf|blend|zip|rar|7z|lys|chitubox)\z/i
    TRANSLITERATIONS = {"\u00e6" => "ae", "\u0153" => "oe", "\u00df" => "ss", "\u00f8" => "o", "\u0142" => "l", "\u0111" => "d", "\u00f0" => "d", "\u00fe" => "th"}.freeze
    Entry = Struct.new(:item, :features, :creator, :index, keyword_init: true)
    Features = Struct.new(:canonical, :words, :numbers, :grams, keyword_init: true)

    class Error < StandardError; end

    def initialize(items)
      invalid! unless items.is_a?(Array) && items.length <= MAX_ITEMS
      ids = {}
      @entries = items.each_with_index.map do |item, index|
        invalid! unless item.is_a?(Hash) && item["id"].is_a?(Integer) && item["id"].positive? &&
          !ids.key?(item["id"]) && valid_text?(item["name"], MAX_ITEM_BYTES) &&
          valid_text?(item["creator_name"], MAX_ITEM_BYTES)
        ids[item["id"]] = true
        Entry.new(item: item, features: features(item["name"]), creator: features(item["creator_name"]), index: index)
      end
    end

    # Strip filename decorations before asking the remote search for candidates.
    # Keep the original local title for ranking and displaying the form.
    def search_query(name)
      return unless valid_text?(name, MAX_QUERY_BYTES)
      query = features(name)
      query.canonical if query && query.words.any?
    end

    # Empty, invalid or excessive queries produce no suggestions. Numeric title
    # variants must agree when the query contains a number; a creator alone can
    # never produce a match. Result limits are capped even for internal callers.
    def matches(name:, creator: nil, limit: 5)
      return [] unless valid_text?(name, MAX_QUERY_BYTES) && limit.is_a?(Integer) && limit.positive?
      query = features(name)
      return [] unless query && !query.words.empty?
      creator_query = valid_text?(creator, MAX_QUERY_BYTES) ? features(creator) : nil
      query_words = query.words.to_h { |word| [word, true] }
      query_grams = query.grams.to_h { |gram| [gram, true] }

      candidates = @entries.filter_map do |entry|
        title = entry.features
        next unless title && !title.words.empty?
        next if !query.numbers.empty? && query.numbers != title.numbers
        shared_words = title.words.count { |word| query_words.key?(word) }
        shared_grams = title.grams.count { |gram| query_grams.key?(gram) }
        dice = (query.grams.length + title.grams.length).zero? ? 0.0 : (2.0 * shared_grams / (query.grams.length + title.grams.length))
        next if shared_words.zero? && dice < 0.28
        exact = query.canonical == title.canonical ? 1 : 0
        preliminary = shared_words.to_f / query.words.length + dice
        creator_score = creator_query && entry.creator ? creator_quality(creator_query, entry.creator) : 0.0
        [entry, exact, preliminary, creator_score]
      end
      candidates.sort_by! { |entry, exact, score, creator_score| [-exact, -score, -creator_score, entry.item["id"], entry.index] }

      ranked = candidates.first(MAX_CANDIDATES).filter_map do |entry, _exact, _preliminary, creator_score|
        title_score = quality(query, entry.features)
        next unless title_score
        [entry, title_score, creator_score]
      end
      ranked.sort_by! { |entry, title_score, creator_score| [-title_score, -creator_score, entry.item["id"], entry.index] }
      ranked.first([limit, MAX_RESULTS].min).map { |entry, _title_score, _creator_score| entry.item }
    end

    private

    def valid_text?(value, maximum)
      value.is_a?(String) && [Encoding::UTF_8, Encoding::US_ASCII].include?(value.encoding) &&
        value.valid_encoding? && value.bytesize <= maximum
    end

    def features(value)
      text = value.encode(Encoding::UTF_8).strip
      # Paths are filename noise only when the name actually ends in a known
      # model/archive extension; slashes in ordinary titles retain their words.
      text = text.split(/[\\\/]/).last.to_s if text.match?(EXTENSION)
      text = text.sub(EXTENSION, "") while text.match?(EXTENSION)
      text = text.gsub(/([[:upper:]])([[:upper:]][[:lower:]])/, '\1 \2')
        .gsub(/([[:lower:][:digit:]])([[:upper:]])/, '\1 \2')
        .gsub(/([[:alpha:]])([[:digit:]])/, '\1 \2')
        .gsub(/([[:digit:]])([[:alpha:]])/, '\1 \2')
        .unicode_normalize(:nfkd).gsub(/\p{M}/, "").downcase
      TRANSLITERATIONS.each { |character, replacement| text = text.gsub(character, replacement) }
      tokens = text.scan(/[[:alnum:]]+/)
      while tokens.length > 1 && FILE_SUFFIXES.include?(tokens.last)
        tokens.pop
        tokens.pop if tokens.last == "pre" && tokens.length > 1
      end
      return nil if tokens.length > MAX_TOKENS
      tokens.each_with_index do |token, index|
        tokens[index] = "version" if token == "v" && tokens[index + 1]&.match?(/\A[0-9]+\z/)
        tokens[index] = token.to_i.to_s if token.match?(/\A[0-9]+\z/)
      end
      tokens = tokens.reject { |token| STOP_WORDS.include?(token) }
      words = tokens.reject { |token| token.match?(/\A[0-9]+\z/) }.uniq
      numbers = tokens.select { |token| token.match?(/\A[0-9]+\z/) }.uniq.sort
      grams = words.sort.join(" ").chars.each_cons(2).map(&:join).uniq
      Features.new(canonical: tokens.join(" "), words: words, numbers: numbers, grams: grams)
    end

    def quality(query, title)
      return 1.0 if query.canonical == title.canonical
      return 0.98 if query.words.sort == title.words.sort && query.numbers == title.numbers
      # A version marker adds no distinction after its numeric variant agrees.
      # Retaining it in canonical titles still ranks a literal title first.
      query_words = query.words
      title_words = title.words
      if !query.numbers.empty? && query.numbers == title.numbers
        query_words = query_words.reject { |word| word == "version" }
        title_words = title_words.reject { |word| word == "version" }
      end
      return nil if query_words.empty? || title_words.empty?
      used_query = {}
      used_title = {}
      title_indices = title_words.each_with_index.to_h
      query_words.each_with_index do |word, index|
        title_index = title_indices[word]
        next unless title_index
        used_query[index] = true
        used_title[title_index] = true
      end
      total = used_query.length.to_f
      unmatched_query = query_words.each_with_index.reject { |_word, index| used_query[index] }
      unmatched_title = title_words.each_with_index.reject { |_word, index| used_title[index] }
      pairs = []
      # Already identical words need no fuzzy comparisons. Extremely verbose
      # unmatched names retain exact-word scoring instead of multiplying work;
      # at most 12 x 12 short token comparisons are made per shortlisted row.
      if unmatched_query.length <= MAX_FUZZY_WORDS && unmatched_title.length <= MAX_FUZZY_WORDS
        unmatched_query.each do |left, left_index|
          unmatched_title.each do |right, right_index|
            similarity = token_similarity(left, right)
            pairs << [similarity, left_index, right_index] if similarity.positive?
          end
        end
      end
      pairs.sort_by! { |similarity, left, right| [-similarity, left, right] }
      pairs.each do |similarity, left, right|
        next if used_query[left] || used_title[right]
        used_query[left] = true
        used_title[right] = true
        total += similarity
      end
      return nil if total.zero?
      query_coverage = total / query_words.length
      title_coverage = total / title_words.length
      all_query_words = used_query.length == query_words.length
      all_title_words = used_title.length == title_words.length
      return nil unless (all_query_words && query_coverage >= 0.74) ||
        (all_title_words && used_query.length >= 2 && query_coverage >= 0.66 && title_coverage >= 0.85)
      score = query_coverage * 0.75 + title_coverage * 0.25
      score += 0.015 if all_query_words && total == query_words.length
      score *= 0.97 if query.numbers.empty? && !title.numbers.empty?
      [score, 0.97].min
    end

    def creator_quality(query, title)
      return 1.0 if !query.canonical.empty? && query.canonical == title.canonical
      return 0.0 if query.words.empty? || title.words.empty?
      (query.words & title.words).length.to_f / (query.words | title.words).length
    end

    def token_similarity(left, right)
      return 1.0 if left == right
      shortest = [left.length, right.length].min
      longest = [left.length, right.length].max
      return 0.0 if shortest < 4 || longest > MAX_TOKEN_CHARS
      maximum = shortest >= 8 ? 2 : 1
      return 0.0 if longest - shortest > maximum
      distance = bounded_distance(left, right, maximum)
      distance ? 1.0 - distance.to_f / longest : 0.0
    end

    # Banded optimal-string-alignment distance also recognizes an adjacent
    # transposition. At most five cells per row are visited; whole names never
    # receive a quadratic edit-distance comparison.
    def bounded_distance(left, right, maximum)
      left_chars = left.chars
      right_chars = right.chars
      previous = (0..right_chars.length).to_a
      before_previous = nil
      left_chars.each_with_index do |character, index|
        row_number = index + 1
        current = Array.new(right_chars.length + 1, maximum + 1)
        current[0] = row_number
        first = [1, row_number - maximum].max
        last = [right_chars.length, row_number + maximum].min
        (first..last).each do |column|
          cost = character == right_chars[column - 1] ? 0 : 1
          value = [previous[column] + 1, current[column - 1] + 1, previous[column - 1] + cost].min
          if before_previous && column > 1 && character == right_chars[column - 2] && left_chars[index - 1] == right_chars[column - 1]
            value = [value, before_previous[column - 2] + 1].min
          end
          current[column] = value
        end
        return nil if current.min > maximum
        before_previous = previous
        previous = current
      end
      distance = previous[right_chars.length]
      distance <= maximum ? distance : nil
    end

    def invalid!
      raise Error, "Printables search suggestions are unavailable for these results.", cause: nil
    end
  end
end
