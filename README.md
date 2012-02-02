Checkpointer
============

Installation
------------

    gem install checkpointer

Why Checkpointer?
-----------------

* Your acceptance test scenarios run the same setup over and over again
* You want to build test data through the application instead of relying on fixtures
* You need to debug a scenario in the application without the hassle of setting it up multiple times.
* You want a convenient way to roll back data changes during development or testing.

Features
--------

* Only saves tables that have changed.
* Works in the rails console with ActiveRecord or in the irb console with Mysql2.
* Multiple checkpoints on a stack
* Named checkpoints
* Restore to any checkpoint at any time.

Limitations
---------

* Runs with Mysql2 or ActiveRecord on Mysql2 only.
* Uses triggers to detect database changes. Any database with existing triggers can't use Checkpointer (yet).
* Becase of triggers, initial setup time is slow.
* Initial backup is also slow, however subsequent backups are much faster.

Alternatives
------------

Database Cleaner is good for transaction-based rollback and truncating tables. It also works on
multiple ORMs and database engines.

Once you start dealing with external tests (e.g. Selenium or Sahi) and longish scenarios with branching test cases,
you should consider Checkpointer.

How to use
----------

```ruby
    require 'checkpointer'
    #=> true
    c = Checkpointer::Checkpointer.new(:database=>'MyApplication_development', :username=>'root', :password=>'')
    #=> <Checkpointer::Checkpointer>
    c.track
    #=> nil
    c.checkpoint 			# Set checkpoints in a stack
    #=> 1
    c.checkpoint 			# Set checkpoints in a stack
    #=> 2
    c.checkpoint "special" 	# Set named checkpoints
    #=> nil
    c.checkpoints 			# List checkpoints
    #=> [1, 2, "special"]

    # Do stuff to the database

    c.restore 				# Restore last checkpoint
    #=> "special"
    c.restore 2				# Restore checkpoint 2 on the stack
    #=> 2
    c.restore "special"		# Restore named checkpoint
    #=> "special"
    c.pop 					# Restore checkpoint 2 from the stack and remove it
    #=> 1

    c.drop 					# Delete checkpoint off the top of the stack
    #=> 0
    c.restore_all 			# Restore all tables if you have problems.
    #=> nil
    c.untrack 				# Stop tracking the database (but why?)
```