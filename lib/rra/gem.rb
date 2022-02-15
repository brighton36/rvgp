require 'jewel'

module RRA
  class Gem < Jewel::Gem
    name! 'rra'
    summary 'A workflow tool to: transform bank-downloaded csv\'s into categorized pta journals. Run finance validations on those journals. And generate reports and graphs on the output.'
    version '0.1'
    homepage 'https://github.com/brighton36/rra'

    author 'Chris DeRose'
    email 'chris@chrisderose.com'

    root '../..'

    # TODO:
    # files `git ls-files`.split "\n"
    # TODO: Let's nix anything that's in the .gitignore maybe, and then just add 
    # ./.git to that
    files `find ./ -type f -not -regex ".*git.*" -printf '%P\n'`.split "\n"

    executables ['rra']

    # TODO: We have more than this
    depend_on :jewel, '0.0.9'
  end
end

