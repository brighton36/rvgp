# frozen_string_literal: true

module RRA
  # This class contains information relating to our Gem configuration, and is
  # used by Jewel, to produce a gemspec.
  class Gem
    GEM_DIR = File.expand_path format('%s/../..', File.dirname(__FILE__))

    class << self
      def specification
        ::Gem::Specification.new do |s|
          s.name        = 'rra'
          s.version     = '0.3'
          s.required_ruby_version = '>= 3.0.0'
          s.licenses    = ['LGPL-2.0']
          s.authors     = ['Chris DeRose']
          s.email       = 'chris@chrisderose.com'
          s.metadata    = { 'source_code_uri' => 'https://github.com/brighton36/rra' }

          s.summary = 'A workflow tool to: transform bank-downloaded csv\'s into ' \
                      'categorized pta journals. Run finance validations on those ' \
                      'journals. And generate csvs and plots on the output.'
          s.homepage = 'https://github.com/brighton36/rra'

          s.files = files

          s.executables = ['rra']

          s.add_development_dependency 'minitest', '~> 5.16.0'
          s.add_development_dependency 'yard', '~> 0.9.34'

          s.add_dependency 'open3', '~> 0.1.1'
          s.add_dependency 'shellwords', '~> 0.1.0'
          s.add_dependency 'google-apis-sheets_v4', '~> 0.22.0'
          s.add_dependency 'faker', '~> 3.2.0'
          s.add_dependency 'finance', '~> 2.0.0'
          s.add_dependency 'tty-table', '~> 0.12.0'
        end
      end

      def files
        # This is a git-less alternative to : `git ls-files`.split "\n"
        `find ./ -type f -printf '%P\n'`.split("\n").reject do |file|
          ignores = ['.git/*'] + File.read(format('%s/.gitignore', GEM_DIR)).split("\n")
          ignores.any? { |glob| File.fnmatch glob, file }
        end
      end

      def ruby_files
        files.select { |f| /\A(?:bin.*|Rakefile|.*\.rb)\Z/.match f }
      end

      def root(sub_path = nil)
        sub_path ? [GEM_DIR, sub_path].join('/') : GEM_DIR
      end
    end
  end
end
