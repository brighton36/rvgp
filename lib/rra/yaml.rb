require 'psych'
require 'pathname'

Psych::add_builtin_type('proc') {|_, val| RRA::Yaml::PsychProc.new val }
Psych::add_builtin_type('include') {|_, val| RRA::Yaml::PsychInclude.new val }

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

      def contents(basedir)
        Psych.load_file(
          (Pathname.new(path).absolute?) ? path : [basedir,path].join('/'),
          symbolize_names: true, permitted_classes: [Date])
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

    attr_reader :path, :basedir, :dependencies

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

    def initialize(path, basedir = nil)
      @path, @dependencies, @basedir = path, [], 
        basedir || File.expand_path(File.dirname(path))

      @yaml = replace_each_in_yaml( 
        Psych.load_file(path, symbolize_names: true, permitted_classes: [Date]),
        PsychInclude ){|psych_inc|
          @dependencies << psych_inc.path
          psych_inc.contents basedir
        }
    end
  end
end

