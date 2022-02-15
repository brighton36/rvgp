module RRA
  module DescendantRegistry
    # We use this in a couple places, to maintain a registry of the available 
    # classes. Usually (always?) inside of RRA
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

      def method_missing(name)
        (@accessors.has_key?(name)) ? @accessors[name].call(self) : super(name)
      end
    end

    def self.included(klass)
      klass.extend ClassMethods
    end

    module ClassMethods
      def register_descendants(in_klass, with_name, opts = {})
        @descendant_registry = {klass: in_klass, name: with_name, 
          name_capture: opts.has_key?(:name_capture) ? opts[:name_capture] : 
            /\A.*\:(.+)\Z/ }
        define_singleton_method(:descendant_registry) { @descendant_registry }

        in_klass.instance_eval do
          iv_sym = ('@%s' % with_name.to_s).to_sym
          instance_variable_set iv_sym, ClassRegistry.new(opts)
          define_singleton_method(with_name) { instance_variable_get iv_sym }
        end
      end

      def inherited(descendant)
        @descendant_registry[:klass].send(@descendant_registry[:name]).add descendant
      end

      def name
        name_capture = self.superclass.descendant_registry[:name_capture]
        name = name_capture.match(self.to_s) ? $1 : self.to_s
        # underscorize the capture:
        name.scan(/[A-Z][^A-Z]+/).join('_').downcase
      end
    end
  end
end
