#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"
	extdir = basedir + "ext"

	$LOAD_PATH.unshift( basedir.to_s ) unless $LOAD_PATH.include?( basedir.to_s )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'

require 'spec/lib/constants'
require 'spec/lib/helpers'

require 'roninshell'
require 'roninshell/mixins'


#####################################################################
###	C O N T E X T S
#####################################################################

describe RoninShell, "mixin" do
	include RoninShell::SpecHelpers

	describe RoninShell::Loggable, "mixed into a class" do
		before(:each) do
			@logfile = StringIO.new('')
			RoninShell.logger = Logger.new( @logfile )

			@test_class = Class.new do
				include RoninShell::Loggable

				def log_test_message( level, msg )
					self.log.send( level, msg )
				end

				def logdebug_test_message( msg )
					self.log_debug.debug( msg )
				end
			end
			@obj = @test_class.new
		end


		it "is able to output to the log via its #log method" do
			@obj.log_test_message( :debug, "debugging message" )
			@logfile.rewind
			@logfile.read.should =~ /debugging message/
		end

		it "is able to output to the log via its #log_debug method" do
			@obj.logdebug_test_message( "sexydrownwatch" )
			@logfile.rewind
			@logfile.read.should =~ /sexydrownwatch/
		end
	end

end

# vim: set nosta noet ts=4 sw=4:
