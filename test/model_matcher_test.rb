# frozen_string_literal: true

require "minitest/autorun"
require "benchmark"
require_relative "../app/services/manyfold_printables/model_matcher"

# Entirely fictional examples; no personal provider account data.
class ModelMatcherTest < Minitest::Test
  Matcher = ManyfoldPrintables::ModelMatcher

  def self.runnable_methods
    super.sort
  end

  def item(id, name, creator: "Example creator")
    {"id" => id, "name" => name, "creator_name" => creator, "creator_id" => 42,
     "tags" => ["miniature"], "sources" => ["URL"], "library_added_at" => 1_800_000_000_000}
  end

  def test_exact_title_ranks_before_fuzzy_and_extra_suffixes_and_returns_original_hashes
    rows = [item(1, "Copper Dragon Bust"), item(2, "Copper Drgaon"), item(3, "Copper Dragon"), item(4, "Copper Elf")]
    before = Marshal.dump(rows)
    result = Matcher.new(rows).matches(name: "Copper Dragon")

    assert_equal [3, 1, 2], result.map { |row| row["id"] }
    assert_same rows[2], result.first
    assert_equal before, Marshal.dump(rows)
  end

  def test_reordered_words_and_filename_decorations_match
    rows = [item(1, "Ancient Copper Dragon"), item(2, "Ancient Copper Elf")]
    matcher = Matcher.new(rows)

    assert_equal [1], matcher.matches(name: "Dragon Copper Ancient").map { |row| row["id"] }
    assert_equal [1], matcher.matches(name: "C:\\models\\Ancient_Copper_Dragon_pre_supported.stl.zip").map { |row| row["id"] }
    assert_equal [1], matcher.matches(name: "Ancient-Copper-Dragon (hollow) (supported).3mf").map { |row| row["id"] }
  end

  def test_remote_search_query_strips_filename_decorations_and_keeps_title_words
    matcher = Matcher.new([])
    assert_equal "copper dragon", matcher.search_query("Copper_Dragon_supported.stl")
    assert_equal "ancient copper dragon", matcher.search_query("C:\\models\\Ancient_Copper_Dragon_pre_supported.stl.zip")
    assert_nil matcher.search_query("1234")
    assert_nil matcher.search_query(" _-- ")
  end

  def test_camelcase_acronyms_punctuation_accents_and_ligatures_are_normalized
    rows = [item(1, "\u00c9lite Clockwork Badger"), item(2, "NOVA Moon Rover"), item(3, "\u00c6ther W\u0153lf"), item(4, "Hollow Knight")]
    matcher = Matcher.new(rows)

    assert_equal [1], matcher.matches(name: "EliteClockworkBadger.stl").map { |row| row["id"] }
    assert_equal [2], matcher.matches(name: "NOVAMoonRover").map { |row| row["id"] }
    assert_equal [3], matcher.matches(name: "Aether_Woelf").map { |row| row["id"] }
    assert_equal [4], matcher.matches(name: "HollowKnight").map { |row| row["id"] }
  end

  def test_small_typos_including_transpositions_and_two_edits_in_long_words_match
    rows = [item(1, "Copper Dragon"), item(2, "Necromancer Captain"), item(3, "Copper Wagon")]
    matcher = Matcher.new(rows)

    assert_equal [1], matcher.matches(name: "Coppre Drgaon").map { |row| row["id"] }
    assert_equal [2], matcher.matches(name: "Necromnacer Captaim").map { |row| row["id"] }
    assert_equal [1], Matcher.new([rows.first]).matches(name: "Coppper Dragon").map { |row| row["id"] }
  end

  def test_numeric_variants_are_preserved_and_leading_zeroes_normalize
    rows = [item(1, "Dragon 1"), item(2, "Dragon 2"), item(3, "Dragon 10"), item(4, "Dragon"), item(5, "Dragon Version 2")]
    matcher = Matcher.new(rows)

    assert_equal [2, 5], matcher.matches(name: "Dragon_02_supported.stl").map { |row| row["id"] }
    assert_equal [5, 2], matcher.matches(name: "Dragon_v2.stl").map { |row| row["id"] }
    assert_equal [3], matcher.matches(name: "Dragon10").map { |row| row["id"] }
    assert_equal 4, matcher.matches(name: "Dragon").first["id"]
    assert_empty matcher.matches(name: "Dragon 3")
  end

  def test_unrelated_rows_short_word_typos_and_creator_only_matches_are_excluded
    rows = [item(1, "Copper Elf", creator: "Wanted studio"), item(2, "Ocean Dragon"), item(3, "Cat"), item(4, "Dragonship"), item(5, "Castle Wall")]
    matcher = Matcher.new(rows)

    assert_empty matcher.matches(name: "Copper Dragon", creator: "Wanted studio")
    assert_empty matcher.matches(name: "Bat", creator: "Wanted studio")
    assert_empty matcher.matches(name: "Dragon", creator: "Wanted studio").select { |row| [1, 4, 5].include?(row["id"]) }
    assert_empty matcher.matches(name: "", creator: "Wanted studio")
  end

  def test_distinctive_single_title_word_can_find_a_long_catalog_title
    rows = [item(7301, "Courier Airship - Zephyrwing - Zephyrwing Cloudrunner Class"), item(2, "Courier Airship Starwind")]

    assert_equal [7301], Matcher.new(rows).matches(name: "Zephyrwing.stl").map { |row| row["id"] }
  end

  def test_creator_breaks_title_ties_without_overriding_a_better_title_match
    rows = [item(1, "Copper Dragon", creator: "Other studio"), item(2, "Copper Dragon", creator: "\u00c9lite Studio"), item(3, "Copper Drgaon", creator: "\u00c9lite Studio")]
    matcher = Matcher.new(rows)

    assert_equal [2, 1, 3], matcher.matches(name: "Copper Dragon", creator: "EliteStudio").map { |row| row["id"] }
    assert_equal [1, 2, 3], matcher.matches(name: "Copper Dragon").map { |row| row["id"] }
  end

  def test_creator_tie_break_applies_before_the_bounded_shortlist
    rows = (1..Matcher::MAX_CANDIDATES + 10).map { |id| item(id, "Copper Dragon", creator: "Other studio") }
    rows << item(999, "Copper Dragon", creator: "Wanted Studio")

    assert_equal 999, Matcher.new(rows).matches(name: "Copper Dragon", creator: "WantedStudio").first["id"]
  end

  def test_limits_empty_invalid_and_excessive_queries_are_bounded
    rows = (1..30).map { |id| item(id, "Copper Dragon") }
    matcher = Matcher.new(rows)

    assert_equal 5, matcher.matches(name: "Copper Dragon").length
    assert_equal 2, matcher.matches(name: "Copper Dragon", limit: 2).length
    assert_equal Matcher::MAX_RESULTS, matcher.matches(name: "Copper Dragon", limit: 100_000).length
    [nil, "", "  _--  ", "the of and", "1234", "x" * (Matcher::MAX_QUERY_BYTES + 1), (["dragon"] * (Matcher::MAX_TOKENS + 1)).join(" "), "\xff".dup.force_encoding(Encoding::UTF_8)].each do |name|
      assert_empty matcher.matches(name: name)
    end
    [0, -1, nil, 1.5, "5"].each { |limit| assert_empty matcher.matches(name: "Copper Dragon", limit: limit) }
    assert_equal [], Matcher.new([]).matches(name: "Copper Dragon")
  end

  def test_invalid_and_oversize_inventory_is_rejected_with_a_fixed_error
    [nil, {}, [item(1, "x" * (Matcher::MAX_ITEM_BYTES + 1))], [item(0, "Dragon")], [item(1, "Dragon"), item(1, "Dragon")], [item(1, "Dragon").merge("creator_name" => nil)], (1..Matcher::MAX_ITEMS + 1).map { |id| item(id, "Dragon") }].each do |rows|
      error = assert_raises(Matcher::Error) { Matcher.new(rows) }
      assert_equal "Printables search suggestions are unavailable for these results.", error.message
      assert_nil error.cause
    end
  end

  def test_large_inventory_keeps_relevant_match_and_has_bounded_runtime
    rows = (1..Matcher::MAX_ITEMS - 1).map { |id| item(id, "Unrelated catalog miniature #{id}") }
    rows << item(Matcher::MAX_ITEMS, "Ancient Copper Dragon")
    matcher = nil
    initialization = Benchmark.realtime { matcher = Matcher.new(rows) }
    result = nil
    elapsed = Benchmark.realtime { result = matcher.matches(name: "Ancient Coppre Drgaon.stl") }

    assert_equal [Matcher::MAX_ITEMS], result.map { |row| row["id"] }
    assert_operator initialization, :<, 15.0, "bounded 20,000-row initialization took #{initialization.round(3)}s"
    assert_operator elapsed, :<, 3.0, "bounded 20,000-row query took #{elapsed.round(3)}s"
    puts "Model matcher 20,000 rows: initialize #{initialization.round(3)}s; query #{elapsed.round(3)}s"
  end

  def test_long_repeated_and_unique_token_names_have_bounded_query_work
    repeated = (["dragon"] * Matcher::MAX_TOKENS).join(" ")
    unique = (0...Matcher::MAX_TOKENS).map { |index| "word#{(97 + index / 26).chr}#{(97 + index % 26).chr}" }.join(" ")
    rows = (1..500).map { |id| item(id, repeated) }
    rows.concat((1001..1500).map { |id| item(id, unique) })
    matcher = Matcher.new(rows)
    elapsed = Benchmark.realtime do
      assert_equal 5, matcher.matches(name: repeated).length
      assert_equal 1001, matcher.matches(name: unique.sub(/wordcl\z/, "wodrcl")).first["id"]
    end

    assert_operator elapsed, :<, 1.0, "bounded repeated-token queries took #{elapsed.round(3)}s"
  end
end
