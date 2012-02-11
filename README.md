Checkpointer
============

Efficiently create and switch between multiple database checkpoints.

Why Checkpointer?
-----------------

* Your acceptance test scenarios run the same setup over and over again
* You want to build test data through the application instead of relying on fixtures
* You need to debug a scenario in the application without the hassle of setting it up multiple times.
* You want a convenient way to roll back data changes during development or testing.

Features
--------

* Checkpoint across schema changes made with ALTER TABLE.
* Tracking persists with multiple connections and sessions. This means that unlike transaction-based checkpoints, you can create another connection to see the current state of the database.
* Works in the rails console with ActiveRecord or in the irb console with Mysql2.
* Checkpoints on a stack or named checkpoints.
* Restore to any checkpoint at any time.
* Only saves tables that have changed.

Installation
------------

In your Gemfile:

    gem 'checkpointer', :git => "git://github.com/bdwong/checkpointer.git"

Usage
-----

### Start tracking the database

```ruby
require 'checkpointer'
#=> true
c = Checkpointer::Checkpointer.new(:database=>'MyApplication_development', :username=>'root', :password=>'mypassword')
#=> <Checkpointer::Checkpointer>
c.track
#=> nil
```

### Scenario 1: Branching test cases

```ruby
# Starting from a newly tracked database...

# Perform common setup for scenario

c.checkpoint "setup"
#=> "setup"

# Perform test case 1

c.restore       # restore to last checkpoint
#=> "setup"

# Perform test case 2

c.restore 0     # restore to clean database for next scenario
#=> 0
```

### Scenario 2: Creating sample data

```ruby
# Starting from a newly tracked database...

```

=== Stop tracking the database

```ruby
c.untrack
```

=== Other commands

```ruby
    c.checkpoints           # List checkpoints
    #=> [1, 2, "special"]

    c.pop                   # Restore checkpoint 2 from the stack and remove it
    #=> 1

    c.drop                  # Delete checkpoint off the top of the stack
    #=> 0
    
    c.restore_all           # Restore all tables if you have problems.
    #=> nil
```

Database Setup
--------------

In order to use checkpointer, your database user must have access to a wildcard set of databases. Your user must have at least the following privilges: CREATE, INSERT, UPDATE, DELETE, DROP, TRIGGER, SHOW DATABASES. If you're not concerned about security, you can grant ALL, or you can use the Mysql root user. Example user setup:

    GRANT ALL ON `database_%`.`*` TO 'dbuser' IDENTIFIED BY 'password';

Limitations
-----------

* Runs with Mysql2 or ActiveRecord on Mysql2 only (pull requests welcome!)
* Uses triggers to detect database changes. Any database with existing triggers can't use Checkpointer (yet).
* Becase of triggers, initial setup time is slow.

Alternatives
------------

Database Cleaner is good for transaction-based rollback and truncating tables. It also works on
multiple ORMs and database engines.

Once you start dealing with external tests (e.g. Selenium or Sahi) and longish scenarios with branching test cases,
you should consider Checkpointer.
