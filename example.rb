require 'sage/checkpointer'

class TestHelper

  def initialize
	config = Rails.configuration.database_configuration[Rails.env]
	@tracker = 	DatabaseTracker.new(config["database"])
  end

  def setup_suite
	@tracker.track
	@tracker.backup
	render :json => {:result => "OK", :message => "Database backed up and tracked"}
  end

  def checkpoint
  	cp = @tracker.checkpoint
	render :json => {:result => "OK", :message => "Checkpoint #{cp} created"}
  end

  def restore
  	cp = params[:cp]
  	@tracker.restore(cp)
	render :json => {:result => "OK", :message => "Checkpoint #{cp} restored"}
  end

  # This action won't work because it needs to remember the checkpoint number.
  def pop
  	@tracker.pop
	render :json => {:result => "Error", :message => "Not implemented"}
  end

  def teardown_suite
  	@tracker.restore(0)
	render :json => {:result => "OK", :message => "Database restored to base state"}
  end

end

require 'sage/checkpointer'

config = Rails.configuration.database_configuration[Rails.env]
#"SageOnePayroll_development"

d = Checkpointer.new(config["database"])
d.track
#d.backup

m = Message.find(1)
n = Message.find(2)
o = Message.find(3)

m.subject = "test1"
m.save
d.checkpoint
n.subject = "test2"
n.save
d.checkpoint
o.subject = "test3"
o.save

d.restore #2
m.reload
n.reload
o.reload

d.restore(2)
m.reload
n.reload
o.reload

d.restore(1)
m.reload
n.reload
o.reload

d.restore(0)
m.reload
n.reload
o.reload

d.untrack

# External use:
#export EVAL_ENGINE_SERVICE_URL="https://ci.dev.onpay.sagebusinessbuilder.com/evalservice/default/-/calculation/$service/runPayrollCalc"
