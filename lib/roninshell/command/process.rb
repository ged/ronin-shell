#!/usr/bin/ruby

require 'logger'
require 'sys/proctable'

require 'roninshell/command'


#--
# A collection of stdobj-based process-related commands for the Ronin Shell.
#
module RoninShell # :nodoc:

	### The 'process' command class.
	class ProcessCommand < RoninShell::Command
		command :process

		### Run the command.
		def run( options, *ignored )
			return Sys::Proctable.ps
		end

	end # RoninShell::ProcessCommand


end # module RoninShell

# vim: set nosta noet ts=4 sw=4:

