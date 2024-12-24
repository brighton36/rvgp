# frozen_string_literal: true

module RVGP
  # There are a handful of calls to pta, that are easily cached for significant performance boosts.
  # This class provides an easy interface to caching and invalidating those calls.
  class CachedPta
    def initialize
      @cache = {}
    end

    def method_missing(*args)
      # NOTE: This isn't entirely sufficient for some cases. .tags being an easy example.
      # .tags runs some of the processing inside ruby, after calling the 'ledger tags'
      # This means that for some grids, we end up with multiple identical calls to ledger
      # and can't cache the first call, because the parameters to .tags changes, and the
      # processing inside tags doesn't leverage the cache. For now, the juice isn't
      # worth the squeeze on accelerating that Particularly since it isn't an rvgp codepath

      @cache[args] ||= RVGP::Pta.pta.send(*args)
    end

    def respond_to_missing?(method_name, include_private = false)
      RVGP::Pta.pta.respond_to? method_name, include_private
    end

    class << self
      def invalidate!(with_path)
        @cached_pta&.reject! { |glob| File.fnmatch? glob, with_path }
      end

      def cached_pta(dependency_glob)
        @cached_pta ||= {}
        @cached_pta[dependency_glob] ||= new
      end
    end
  end
end
