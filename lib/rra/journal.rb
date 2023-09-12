# frozen_string_literal: true

require_relative 'journal/journal'
require_relative 'journal/currency'
require_relative 'journal/commodity'
require_relative 'journal/complex_commodity'
require_relative 'journal/posting'

class String # rubocop:disable Style/Documentation
  def to_commodity
    RRA::Journal::Commodity.from_s self
  end

  def to_tag
    RRA::Journal::Posting::Tag.from_s self
  end
end
