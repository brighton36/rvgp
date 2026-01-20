# frozen_string_literal: true

require 'psych'
require 'pathname'

Psych.add_builtin_type('proc') { |_, val| RVGP::Utilities::Yaml::PsychProc.new val }
Psych.add_builtin_type('include') { |_, val| RVGP::Utilities::Yaml::PsychInclude.new val }

module RVGP
  module Utilities
    # This class wraps the Psych library, and adds functionality we need, to parse
    # yaml files.
    # We mostly added this class because the Psych.add_builtin_type wasn't able to
    # contain state outside it's return values. (which we need, in order to
    # track include dependencies)
    class Yaml
      # This class is needed, in order to capture the dependencies needed to
      # properly preserve uptodate status in rake builds
      class PsychInclude
        attr_reader :path

        # Declare a proc, given the provided proc_as_string code
        # @param [String] path A relative or absolute path, to include, in the place of this line
        def initialize(path)
          @path = path
        end

        # The contents of this include target.
        # @param [Array<String>] include_paths A relative or absolute path, to include, in case our path is relative
        #                                      and we need to load it from a relative location. These paths are
        #                                      scanned for the include, in the relative order of their place in the
        #                                      array.
        # @return [Hash] The contents of the target of this include. Keys are symbolized, and permitted_classes include
        #                Date, and Symbol
        def contents(include_paths)
          content_path = path if Pathname.new(path).absolute?
          content_path ||= include_paths.map { |p| [p.chomp('/'), path].join('/') }.find do |p|
            File.readable? p
          end

          unless content_path
            raise StandardError, format('Unable to find %<path>s in any of the provided paths: %<paths>s',
                                        path: path.inspect, paths: include_paths.inspect)
          end

          Psych.safe_load_file content_path, symbolize_names: true, permitted_classes: [Date, Symbol]
        end
      end

      # This class wraps proc types, in the yaml, and offers us the ability to execute
      # the code in these blocks.
      class PsychProc
        # Declare a proc, given the provided proc_as_string code
        # @param [String] proc_as_string Ruby code, that this block will call.
        def initialize(proc_as_string)
          @block = eval(format('proc { %s }', proc_as_string)) # rubocop:disable Security/Eval
        end

        # Execute the block, using the provided params as locals
        # NOTE: We expect symbol to value here
        # @param params [Hash<Symbol, Object>] local values, available in the proc context. Note that keys
        #                                      are expected to be symbols.
        # @return [Object] Whatever the proc returns
        def call(params = {})
          # params, here, act as instance variables, since we don't support named
          # params in the provided string, the way you typically would.
          @params = params
          @block.call
        end

        # @!visibility private
        def respond_to_missing?(name, _include_private = false)
          @params&.key?(name.to_sym)
        end

        # @!visibility private
        def method_missing(name)
          respond_to_missing?(name) ? @params[name] : super(name)
        end
      end

      attr_reader :path, :include_paths, :dependencies

      # @param [String] path The full path to the yaml file you wish to parse
      # @param [Array<String>] include_paths An array of directories, to search, when locating the target of
      #                                      a "!!include" line
      def initialize(path, include_paths = nil)
        @path = path
        @dependencies = []
        @include_paths = Array(include_paths || File.expand_path(File.dirname(path)))

        vanilla_yaml = Psych.safe_load_file(path, symbolize_names: true, permitted_classes: [Date, Symbol])
        @yaml = replace_each_in_yaml(vanilla_yaml, PsychInclude) do |psych_inc|
          @dependencies << psych_inc.path
          psych_inc.contents @include_paths
        end
      end

      # Return the specified attribute, in this yaml file
      # @param [String] attr The attribute you're looking for
      # @return [Object] The value of the the provided attribute
      def [](attr)
        @yaml&.[](attr)
      end

      # Returns true or false, depending on whether the attribute you're looking for, exists in this
      # yaml file.
      # @param [String] attr The attribute you're looking for
      # @return [TrueClass,FalseClass] Whether the key is defined in this file
      def key?(attr)
        @yaml&.key? attr
      end

      def to_h
        @yaml.to_h
      end

      alias has_key? key?

      private

      # This is kind of a goofy function, but, it works
      def replace_each_in_yaml(obj, of_class, &blk)
        case obj
        when Hash
          obj.transform_values { |v| replace_each_in_yaml v, of_class, &blk }
        when Array
          obj.collect { |v| replace_each_in_yaml(v, of_class, &blk) }
        else
          obj.is_a?(of_class) ? blk.call(obj) : obj
        end
      end
    end
  end
end
