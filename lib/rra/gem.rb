require 'jewel'

module RRA
  class Gem < Jewel::Gem
    GEM_DIR = File.expand_path '%s/../..' % File.dirname(__FILE__)

    name! 'rra'
    summary 'A workflow tool to: transform bank-downloaded csv\'s into categorized pta journals. Run finance validations on those journals. And generate reports and graphs on the output.'
    version '0.1'
    homepage 'https://github.com/brighton36/rra'
    license 'LGPL-2.0'

    author 'Chris DeRose'
    email 'chris@chrisderose.com'

    root GEM_DIR
    require_paths = ['lib']

    # This is an alternative to below. But, sometimes I test out builds that
    # aren't git-committed:
    # files `git ls-files`.split "\n"
    ignores = ['.git/*']+File.read('%s/.gitignore' % GEM_DIR).lines.collect(&:chomp)

    files `find ./ -type f -printf '%P\n'`\
      .split("\n")\
      .reject{|file| ignores.any?{|glob| File.fnmatch glob, file} }

    executables ['rra']

    depend_on :jewel, '~> 0.0.9'
    depend_on :finance, '~> 2.0.0'
    depend_on 'tty-table', '~> 0.12.0'
  end
end

