# frozen_string_literal: true

module RRA
  module Validations
    # This class implements a journal validation that ensures a given transfer, hasn't
    # been tagged more than once, with the same tag.
    class DuplicateTagsValidation < RRA::Base::JournalValidation
      # Reviews every transfer, and post, to ensure that there are no tags occurring more than once, in
      # any given entry. Unlike most of the validations in RRA, this one doesn't use ledger or hledger
      # to validate. This validation parses the file itself, in ruby, and ensures based on the contents.
      def validate
        journal = RRA::Journal.parse File.read(transformer.output_file)
        dupe_messages = []

        journal.postings.each do |posting|
          posting_tag_names = posting.tags.map(&:key)
          found_dupes = posting_tag_names.find_all { |tag| posting_tag_names.count(tag) > 1 }.uniq

          if found_dupes.empty?
            posting.transfers.each do |transfer|
              transfer_tag_names = transfer.tags.map(&:key) + posting_tag_names

              found_dupes = transfer_tag_names.find_all { |tag| transfer_tag_names.count(tag) > 1 }.uniq

              next if found_dupes.empty?

              dupe_messages << format('Line %<line>d: %<date>s %<desc>s (Transfer: %<tags>s)',
                                      line: posting.line_number,
                                      date: posting.date,
                                      desc: posting.description,
                                      tags: found_dupes.join(', '))
            end
          else
            dupe_messages << format('Line %<line>d: %<date>s %<desc>s (%<tags>s)',
                                    line: posting.line_number,
                                    date: posting.date,
                                    desc: posting.description,
                                    tags: found_dupes.join(','))
          end
        end

        unless dupe_messages.empty?
          error! 'These postings have been tagged with the same tag, more than once', dupe_messages
        end
      end
    end
  end
end
