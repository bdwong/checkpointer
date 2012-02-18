require "bundler/gem_tasks"
begin
  require 'simplecov'
rescue LoadError
end
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new('spec')

 task :default => :spec

desc  "Run all specs with rcov"
RSpec::Core::RakeTask.new(:rcov) do |t|
  t.rcov = true
  t.rcov_opts = %w{--exclude ~/.rvm\/,spec\/,features\/}
end
