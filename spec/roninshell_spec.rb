#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent

	libdir = basedir + "lib"
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'spec'
require 'spec/lib/constants'
require 'spec/lib/helpers'

require 'roninshell'
require 'roninshell/cli'

include RoninShell::TestConstants
include RoninShell::Constants

#####################################################################
###	C O N T E X T S
#####################################################################

describe RoninShell do
	include RoninShell::SpecHelpers


	before( :all ) do
		setup_logging( :debug )
	end


	it "parses its options and starts a command line when started" do
		optparser = mock( "Option parser" )
		OptionParser.stub!( :new ).and_return( optparser )

		options = mock( "options ostruct" )
		OpenStruct.stub!( :new ).and_return( options )
		argv = []
		remainder = []
		cli = mock( "command line interface" )

		optparser.should_receive( :parse! ).with( argv ).and_return( remainder )
		RoninShell::CLI.should_receive( :new ).with( options ).and_return( cli )
		cli.should_receive( :run )

		RoninShell.start( argv )
	end

end

# vim: set nosta noet ts=4 sw=4:
