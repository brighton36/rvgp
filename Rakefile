task default: "test"

require_relative 'lib/rra'

desc "Run the minitests"
task :test do
  Dir[RRA::Gem.root.test('test*.rb')].each{|f| require f}
end

