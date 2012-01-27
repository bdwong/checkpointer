# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "checkpointer/version"

Gem::Specification.new do |s|
  s.name        = "checkpointer"
  s.version     = Checkpointer::VERSION
  s.authors     = ["Brian Wong"]
  s.email       = ["bdwong.net@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{Checkpoint and restore databases during development and acceptance tests.}
  s.description = %q{ Use Checkpoint on a MySQL database to save and restore database state during
                      development and acceptance tests. Uses ActiveRecord directly if available,
                      or Mysql2 gem if not.
                    }

  s.rubyforge_project = "checkpointer"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "rspec"
  s.add_development_dependency "activerecord"
  s.add_runtime_dependency "mysql2"
  # s.add_runtime_dependency "rest-client"
end
