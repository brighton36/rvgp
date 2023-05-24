# frozen_string_literal: true

require 'psych'
require 'pathname'

Psych.add_builtin_type('proc') { |_, val| RRA::Yaml::PsychProc.new val }
Psych.add_builtin_type('include') { |_, val| RRA::Yaml::PsychInclude.new val }

module RRA
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

      def initialize(path)
        @path = path
      end

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
      def initialize(proc_as_string)
        @block = eval(format('proc { %s }', proc_as_string)) # rubocop:disable Security/Eval
      end

      # params, here, act as instance variables, since we don't support named
      # params in the provided string, the way you typically would.
      # NOTE: We expect symbol to value here
      def call(params = {})
        @params = params
        @block.call
      end

      def respond_to_missing?(name)
        @params&.key?(name.to_sym)
      end

      def method_missing(name)
        respond_to_missing?(name) ? @params[name] : super(name)
      end
    end

    attr_reader :path, :include_paths, :dependencies

    def [](attr)
      @yaml&.[](attr)
    end

    def key?(attr)
      @yaml&.key? attr
    end

    alias has_key? key?

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
  end
end
