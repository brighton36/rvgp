# frozen_string_literal: true

module RVGP
  # There are a handful of calls to pta, that are easily cached for significant performance boosts.
  # This class directs all queries to {RVGP::Pta::AvailabilityHelper.pta}, and caches it's output, for use in subsequent
  # queries.
  #
  # The caching itself is managed by {CachedPta.cached_pta} and {CachedPta.invalidate!}. An instance of this
  # class is expected to be created by the {CachedPta.cached_pta} method. And, that instance is declared
  # contigent upon the freshness of a file glob. When a call is made to {CachedPta.invalidate!}, and the
  # file that was invalidated, matches the cache glob - the instance of CachedPta is destroyed, and the cache
  # is no longer stored. (Thus ensuring a subsequent call won't use the cache)
  class CachedPta
    def initialize
      @cache = {}
    end

    # All the methods defined in {RVGP::Pta::AvailabilityHelper.pta} are available here in this class. However, the
    # method_missing will proxy those calls, and cache their return. If the cache is availble, for a query, who
    # parameters exactly match a prior query, we return that cache instead of calling pta.
    def method_missing(*args)
      # NOTE: This isn't entirely sufficient for some cases. .tags being an easy example.
      # .tags runs some of the processing inside ruby, after calling the 'ledger tags'
      # This means that for some grids, we end up with multiple identical calls to ledger
      # and can't cache the first call, because the parameters to .tags changes, and the
      # processing inside tags doesn't leverage the cache. For now, the juice isn't
      # worth the squeeze on accelerating that Particularly since it isn't an rvgp codepath

      @cache[args] ||= RVGP::Pta.pta.send(*args)
    end

    # This method is required by ruby, and requests are proxied to {RVGP::Pta::AvailabilityHelper.pta#respond_to?}
    def respond_to_missing?(method_name, include_private = false)
      RVGP::Pta.pta.respond_to? method_name, include_private
    end

    class << self
      # This method will destroy any {RVGP::CachedPta} instances which were created by a glob, that matches against
      # the provided with_path.
      # @param [String] with_path A filesystem path, to the file that was modified
      def invalidate!(with_path)
        # NOTE: We have the option, of automatically invalidating the cache, by way of accessing mtimes.
        # for the provided glob. For now, I prefer manually instigation.
        @cached_pta&.reject! { |glob| File.fnmatch? glob, with_path }
      end

      # Create a pta query cache, which is dependent on the freshness of the provided dependency_glob. When a file
      # is changed, that is matched by this glob - the cache will be flushed, and the subsequent query will be
      # regenerated.
      # @param [String] dependency_glob A glob, that indicates what files this cache is contigent upon. "*.journal"
      #                                 is particularly helpful. But, any path should work, so long as the codebase
      #                                 is manually triggering a call to {RVGP::CachedPta.invalidate!} upon mutation.
      #                                 (which is the case for RVGP. Your code may be required to call this as well)
      # @return [RVGP::CachedPta] A proxy object, between the caller, and {RVGP::Pta::AvailabilityHelper.pta}
      def cached_pta(dependency_glob)
        @cached_pta ||= {}
        @cached_pta[dependency_glob] ||= new
      end
    end
  end
end
