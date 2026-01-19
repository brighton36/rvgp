# frozen_string_literal: true

module RVGP
  # This class parses a pta journal, and offers that journal in its constitutent
  # parts. See the {Journal::PtaFile.parse} for the typical entry point, into this class.
  # This class itself, really only offers the one method, .parse, to parse a pta
  # journal's contents. Most of the functionality in this class, is provided
  # by the classes contained within it.
  # @attr_reader [Array<RVGP::Journal::Posting>] postings The postings that were encountered in this journal
  module Journal
    class PtaFile
      # @!visibility private
      MSG_MISSING_POSTING_SEPARATOR = 'Missing a blank line before line %d: %s'
      # @!visibility private
      MSG_UNRECOGNIZED_HEADER = 'Unrecognized posting header at line %d: %s'
      # @!visibility private
      MSG_INVALID_DATE = 'Invalid posting date at line %d: %s'
      # @!visibility private
      MSG_UNEXPECTED_TRANSFER = 'Unexpected transfer at line %d: %s'
      # @!visibility private
      MSG_UNEXPECTED_TAG = 'Unexpected tag at line %d: %s'
      # @!visibility private
      MSG_UNEXPECTED_LINE = 'Unexpected at line %d: %s'
      # @!visibility private
      MSG_INVALID_TRANSFER_COMMODITY = 'Unparseable or unimplemented commodity-parse in transfer at line %d: %s'
      # @!visibility private
      MSG_INVALID_POSTING = 'Invalid Posting at separator line %d: %s'
      # @!visibility private
      MSG_TOO_MANY_SEMICOLONS = 'Too many semicolons at line %d. Are these comments? %s'
      # @!visibility private
      MSG_UNPARSEABLE_TRANSFER = 'Something is wrong with this transfer at line %d: %s'

      attr :postings

      # Declare and initialize this file.
      # @param [Array[RVGP::Journal::Posting]] postings An array of postings that this instance represents
      def initialize(postings)
        @postings = postings
      end

      # Unparse this journal, and return the parsed objects in their serialized form.
      # @return [String] A pta journal. Presumably, the same one we were initialized from
      def to_s
        @postings.map(&:to_ledger).join "\n\n"
      end

      # Given a pta journal, already read from the filesystem, return a parsed representation of its contents.
      # @param [String] contents A pta journal, as a string
      # @return [RVGP::Journal] The parsed representation of the provided string
      def self.parse(contents)
        postings = []

        posting = nil
        cite = nil
        contents.lines.each_with_index do |line, i|
          next if posting.nil? && postings.empty? && /\A;/.match(line)

          line_number = i + 1
          cite = [line_number, ': ', line.inspect].join # in case we run into an error
          line_comment = nil

          # Here, we separate the line into non-comment lvalue and comment rvalue:
          # NOTE: We're not supporting escaped semicolons, at this time
          case line
          when /\A.*[^\\];.*[^\\];.*\Z/
            raise StandardError, format(MSG_TOO_MANY_SEMICOLONS, cite)
          when /\A( *.*?) *;[ \t]*(.*)\Z/
            line = ::Regexp.last_match(1)
            line_comment = ::Regexp.last_match(2)
          end

          # This case parses anything to the left of a comment:
          case line
          when /\A([^ \n].*)\Z/
            # This is a post declaration line
            raise StandardError, MSG_MISSING_POSTING_SEPARATOR % cite if posting
            unless %r{\A(\d{4})[/-](\d{2})[/-](\d{2}) +(.+?) *\Z}.match ::Regexp.last_match(1)
              raise StandardError, MSG_UNRECOGNIZED_HEADER % cite
            end

            begin
              date = Date.new ::Regexp.last_match(1).to_i, ::Regexp.last_match(2).to_i, ::Regexp.last_match(3).to_i
            rescue Date::Error
              raise StandardError, MSG_INVALID_DATE % cite
            end

            posting = Posting.new date, ::Regexp.last_match(4), line_number: line_number
          when /\A[ \t]+([^ ].+)\Z/
            # This is a transfer line, to be appended to the current posting
            raise StandardError, MSG_UNEXPECTED_TRANSFER % cite unless posting

            # NOTE: We chose 2 or more spaces as the separator between
            # the account and the commodity, mostly because this was the smallest
            # we could find in the official ledger documentation
            unless /\A(.+?)(?: {2,}([^ ].+)| *)\Z/.match ::Regexp.last_match(1)
              raise StandardError, format(MSG_UNPARSEABLE_TRANSFER, cite)
            end

            begin
              posting.append_transfer ::Regexp.last_match(1), ::Regexp.last_match(2)
            rescue RVGP::Journal::Commodity::Error
              raise StandardError, MSG_INVALID_TRANSFER_COMMODITY % cite
            end
          when /\A[ \t]*\Z/
            if line_comment.nil? && posting
              unless posting.valid?
                posting.transfers.each do |transfer|
                  puts format('  - Not valid. account %<acct>s commodity: %<commodity>s complex_commodity: %<complex>s',
                              acct: transfer.account.inspect,
                              commodity: transfer.commodity.inspect,
                              complex: transfer.complex_commodity.inspect)
                end
              end

              raise StandardError, MSG_INVALID_POSTING % cite unless posting.valid?

              # This is a blank line
              postings << posting
              posting = nil
            end
          else
            raise StandardError, MSG_UNEXPECTED_LINE % cite unless posting
          end

          next unless line_comment && posting

          tags = line_comment.scan(/(?:[^ ]+: *[^,]*|:[^ \t]+:)/).map do |declaration|
            /\A:?(.+):\Z/.match(declaration) ? ::Regexp.last_match(1).split(':') : declaration
          end.flatten

          tags.each { |tag| posting.append_tag tag }
        end

        # The last line could be \n, which, makes this unnecessary
        if posting
          raise StandardError, MSG_INVALID_POSTING % cite unless posting.valid?

          postings << posting
        end

        new postings
      end
    end
  end
end
