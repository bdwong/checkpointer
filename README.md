
How to use
==

require 'checkpointer'
#=> true
c = Checkpointer::Checkpointer.new(:database=>'SageOnePayroll_development', :username=>'root', :password=>'')
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
c.pop 					# Restore checkpoint on the stack and pop it off
#=> 1

c.drop 					# Delete checkpoint off the top of the stack
#=> 0
c.restore_all 			# Restore all tables if you have problems.
#=> nil
c.untrack 				# Stop tracking the database
