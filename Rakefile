require "bundler/gem_tasks"
begin
  require 'simplecov'
  coverage_type = :simplecov
rescue LoadError
  coverage_type = :rcov
end
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new('spec')

 task :default => :spec

if coverage_type == :rcov
  RSpec::Core::RakeTask.new(:rcov) do |t|
    t.rcov = true
    t.rcov_opts = %w{--exclude ~/.rvm/,spec/,features/}
  end
end

if coverage_type == :simplecov
  RSpec::Core::RakeTask.new(:simplecov) do |t|
    ENV["COVERAGE"]="true"
  end
end

desc  "Run all specs with code coverage"
task :coverage do
  Rake::Task[coverage_type].invoke
end
