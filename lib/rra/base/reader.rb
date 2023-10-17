# frozen_string_literal: true

module RRA
  module Base
    # This base class exists as a shorthand, for classes whose public readers are populated via
    # #initialize(). Think of this as an lighter-weight alternative to OpenStruct.
    # @attr_reader [Hash<Symbol,Object>] options This instance's reader attributes, and their values, as a Hash
    class Reader
      # Classes which inherit from this class, can declare their attr_reader in a shorthand format, by way of
      # this method. Attributes declared in this method, will be able to be set in the options passed to
      # their #initialize
      # @param readers [Array<Symbol>] A list of the attr_readers, this class will provide
      def self.readers(*readers)
        attr_reader(*readers)
        attr_reader :options

        define_method :initialize do |*args|
          readers.each_with_index do |r, i|
            instance_variable_set format('@%s', r).to_sym, args[i]
          end

          # If there are more arguments than attr's the last argument is an options
          # hash
          instance_variable_set '@options', args[readers.length].is_a?(Hash) ? args[readers.length] : {}
        end
      end
    end
  end
end
