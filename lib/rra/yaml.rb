require 'psych'
require 'pathname'

Psych::add_builtin_type('proc') { |_, val| RRA::Yaml::PsychProc.new val }
Psych::add_builtin_type('include') { |_, val| RRA::Yaml::PsychInclude.new val }

module RRA
  # We added this class because the Psych.add_builtin_type wasn't able to 
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
        content_path = if Pathname.new(path).absolute?
          path
        else
          include_paths.map { |p| [p.chomp('/'), path].join('/') }.find do |p|
            File.readable? p
          end
        end

        raise StandardError, "Unable to find %s in any of the provided paths: %s" % [
          path.inspect, include_paths.inspect ] unless content_path

        Psych.safe_load_file content_path, symbolize_names: true, 
          permitted_classes: [Date, Symbol]
      end
    end

    class PsychProc
      def initialize(proc_as_string)
        @block = eval("proc { %s }" % proc_as_string)
      end

      # params, here, act as instance variables, since we don't support named
      # params in the provided string, the way you typically would.
      # NOTE: We expect symbol to value here
      def call(params = {})
        @params = params
        @block.call
      end

      def method_missing(name)
        (@params and @params.has_key? name.to_sym) ? @params[name] : super(name)
      end
    end

    attr_reader :path, :include_paths, :dependencies

    def [](attr); @yaml[attr]; end
    def has_key?(attr); @yaml.has_key? attr; end

    # This is kind of a goofy function, but, it works
    def replace_each_in_yaml(obj, of_class,  &blk)
      case obj
        when Hash
          Hash[obj.collect{|k,v| [k, replace_each_in_yaml(v, of_class, &blk)] }]
        when Array
          obj.collect{|v| replace_each_in_yaml(v, of_class, &blk) }
        else
          obj.kind_of?(of_class) ? blk.call(obj) : obj
      end
    end

    def initialize(path, include_paths = nil)
      @path, @dependencies, @include_paths = path, [], 
        Array(include_paths || File.expand_path(File.dirname(path)))
      
      @yaml = replace_each_in_yaml( 
        Psych.safe_load_file(path, symbolize_names: true, permitted_classes: [Date, Symbol]),
        PsychInclude ) {|psych_inc|
          @dependencies << psych_inc.path
          psych_inc.contents @include_paths
        }
    end
  end
end

