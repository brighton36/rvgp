# frozen_string_literal: true

require_relative 'journal/journal'
require_relative 'journal/currency'
require_relative 'journal/commodity'
require_relative 'journal/complex_commodity'
require_relative 'journal/posting'

# Extensions to the ruby stdlib implementation of String. Offered as a convenience.
class String
  # Given a string, such as "$ 20.57", or "1 MERCEDESBENZ", Construct and return a {RRA::Journal::Commodity}
  # representation.
  # see {RRA::Journal::Commodity.from_s}
  # @return [RRA::Journal::Commodity] the parsed string
  def to_commodity
    RRA::Journal::Commodity.from_s self
  end

  # Parse a string, into a {RRA::Journal::Posting::Tag} object
  # see {RRA::Journal::Posting::Tag.from_s}
  def to_tag
    RRA::Journal::Posting::Tag.from_s self
  end
end
