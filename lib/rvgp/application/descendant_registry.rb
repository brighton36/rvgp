# frozen_string_literal: true

module RVGP
  class Application
    # This module contains a system by which RVGP maintains an application registry,
    # of child classes, for a given parent class. These registries are stored in
    # the RVGP namespace, under a provided name (usually something resembling the
    # superclass name), and facilitates an easy form of child class enumeration,
    # throughout the RVGP system.
    #
    # Thus far, the parent classes which are using this functionality, are:
    # {RVGP::Base::Command}, {RVGP::Base::Grid}, {RVGP::Base::JournalValidation}, and {RVGP::Base::SystemValidation}.
    #
    # This means that, for example, a class which inherits from {RVGP::Base::Command},
    # is added to the array of its siblings in {RVGP.commands}. Similarly, there are
    # containers for {RVGP.grids}, {RVGP.journal_validations}, and {RVGP.system_validations}.
    module DescendantRegistry
      # This basic class resembles an array, and is used to house a regsitry of
      # children classes. Typically, this class is instantiated inside of RVGP, at
      # the time a child inherits from a parent.
      #
      # @attr_reader [Array<Object>] classes The undecorated classes that are contained in this object
      class ClassRegistry
        include Enumerable

        attr_reader :classes

        # Declare the registry, and initialize with the relevant options
        # @param [Hash] opts what options to configure this registry with
        # @option opts [Hash<String, Proc>] :accessors what methods to dispatch to the instances of this collection
        def initialize(opts = {})
          @classes = []
          @accessors = opts[:accessors] || {}
        end

        # Call the provided block, for each element of the registry
        # @yield [obj] The block you wish to call, once per element of the registry
        # @return [void]
        def each(&block)
          classes.each(&block)
        end

        # Add the provided object to the {#classes} collection
        # @param [Object] klass The object class, you wish to add
        # @return [void]
        def add(klass)
          @classes << klass
        end

        # The names of all the classes that are defined in this registry
        # @return [Array<String>]
        def names
          classes.collect(&:name)
        end

        # @!visibility private
        def respond_to_missing?(name, _include_private = false)
          @accessors.key? name
        end

        # In the case that a method is called on this registry, that isn't explicitly defined,
        # this method checks the accessors provided in {#initialize} to see if there's a matching
        # block, indexing to the name of the missing method. And calls that.
        # @param [Symbol] name The method attempting to be called
        def method_missing(name)
          @accessors.key?(name) ? @accessors[name].call(self) : super(name)
        end
      end

      # @!visibility private
      def self.included(klass)
        klass.extend ClassMethods
      end

      # This module defines the parent's class methods, which are attached to a parent
      # class, at the time it includes the DescendantRegistry
      module ClassMethods
        # This method is the main entrypoint for all of the descendent registry features. This method
        # installs a registry, into the provided namespace, given the provided options
        # @param [Object] in_klass This is class, under which, this registry will be created
        # @param [Symbol] with_name The name of the registry, which will be the name of the reader, created in in_klass
        # @param [Hash] opts what options to configure this registry with
        # @option opts [Hash<String, Proc>] :accessors A list of public methods to create, alongside their
        #                                              implementation,in the base of the newly created collection.
        # @option opts [Regexp] :name_capture This regex is expected to contain a single capture, that will be used to
        #                                     construct a class name, given a classes #to_s output, and before sending
        #                                     to underscorize.
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

        # The name of this base class, after applying its to_s to :name_capture,
        # and underscore'izing the capture
        # @return [String] A string that can be used for various metaprogramming requirements of this
        #                  DescendantRegistry
        def name
          name_capture = superclass.descendant_registry[:name_capture]
          name = name_capture.match(to_s) ? ::Regexp.last_match(1) : to_s

          # underscorize the capture:
          name.scan(/[A-Z][^A-Z]*/).join('_').downcase
        end

        private

        def inherited(descendant)
          super(descendant)
          @descendant_registry[:klass].send(@descendant_registry[:name]).add descendant
        end
      end
    end
  end
end
