# frozen_string_literal: true

module RRA
  # This module contains a system by which RRA maintains an application registry,
  # of child classes, for a given parent class. These registries are stored in
  # the RRA namespace, under a provided name (usually something resembling the
  # superclass name), and facilitates an easy form of child class enumeration,
  # throughout the RRA system.
  #
  # Thus far, the parent classes which are using this functionality, are:
  #   RRA::Base::Command, RRA::Base::Grid, RRA::Base::JournalValidation, and RRA::Base::SystemValidation.
  #
  # This means that, for example, a class which inherits from RRA::Base::Command,
  # is added to the array of its siblings in RRA.commands. Similarly, there are
  # containers for RRA.grids, RRA.journal_validations, and RRA.system_validations.
  module DescendantRegistry
    # This basic class resembles an array, and is used to house a regsitry of
    # children classes. Typically, this class is instantiated inside of RRA, at
    # the time a child inherits from a parent.
    class ClassRegistry
      include Enumerable

      attr_reader :classes

      def initialize(opts = {})
        @classes = []
        @accessors = opts[:accessors] || {}
      end

      def each(&block)
        classes.each(&block)
      end

      def add(klass)
        @classes << klass
      end

      def names
        classes.collect(&:name)
      end

      def respond_to_missing?(name, _include_private = false)
        @accessors.key? name
      end

      def method_missing(name)
        @accessors.key?(name) ? @accessors[name].call(self) : super(name)
      end
    end

    def self.included(klass)
      klass.extend ClassMethods
    end

    # This module defines the parent's class methods, which are attached to a parent
    # class, at the time it includes the DescendantRegistry
    module ClassMethods
      def register_descendants(in_klass, with_name, opts = {})
        @descendant_registry = { klass: in_klass,
                                 name: with_name,
                                 name_capture: opts.key?(:name_capture) ? opts[:name_capture] : /\A.*:(.+)\Z/ }
        define_singleton_method(:descendant_registry) { @descendant_registry }

        in_klass.instance_eval do
          iv_sym = "@#{with_name}".to_sym
          instance_variable_set iv_sym, ClassRegistry.new(opts)
          define_singleton_method(with_name) { instance_variable_get iv_sym }
        end
      end

      def inherited(descendant)
        super(descendant)
        @descendant_registry[:klass].send(@descendant_registry[:name]).add descendant
      end

      def name
        name_capture = superclass.descendant_registry[:name_capture]
        name = name_capture.match(to_s) ? ::Regexp.last_match(1) : to_s
        # underscorize the capture:
        name.scan(/[A-Z][^A-Z]+/).join('_').downcase
      end
    end
  end
end
