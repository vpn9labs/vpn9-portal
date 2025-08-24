#
# Wordlist provides cached access to adjective and noun lists used for
# generating human-friendly device names. This is a plain Ruby model with no
# database table.
#
# Sources
# - db/english-adjectives.txt
# - db/english-nouns.txt
#
# The lists are sanitized by trimming whitespace, removing empties, and
# removing hyphens from compound words for nicer device names.
#
class Wordlist
  class << self
    # Adjective list for name generation.
    # @return [Array<String>]
    def adjectives
      @adjectives ||= load_word_list("db/english-adjectives.txt")
    end

    # Noun list for name generation.
    # @return [Array<String>]
    def nouns
      @nouns ||= load_word_list("db/english-nouns.txt")
    end

    # Clear caches and reload word lists from disk.
    # @return [void]
    def reload!
      @adjectives = nil
      @nouns = nil
      adjectives
      nouns
    end

    private

    # Load and sanitize a word list file.
    # Removes empty lines and hyphens.
    #
    # @param file_path [String]
    # @return [Array<String>]
    def load_word_list(file_path)
      full_path = Rails.root.join(file_path)

      unless File.exist?(full_path)
        Rails.logger.warn "Word list file not found: #{file_path}"
        return []
      end

      words = File.readlines(full_path)
                   .map(&:strip)
                   .reject(&:empty?)
                   .map { |word| word.gsub("-", "") }

      if words.empty?
        Rails.logger.warn "Word list file is empty: #{file_path}"
        return []
      end

      Rails.logger.info "Loaded #{words.length} words from #{file_path}"
      words
    rescue StandardError => e
      Rails.logger.error "Error loading word list from #{file_path}: #{e.message}"
      []
    end
  end
end
