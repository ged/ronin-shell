#!/usr/bin/ruby

require 'logger'
require 'roninshell/command'


#--
# A collection of builtin commands for the Ronin Shell.
#
module RoninShell # :nodoc:

	### The 'cd' command class.
	class CdCommand < RoninShell::Command
		command :cd

		### Run the command.
		def run( options, target, *ignored )
			full_path = File.expand_path( target, Dir.pwd )
			Dir.chdir( full_path )
			self.cli.message( full_path )
		end

	end # RoninShell::CdCommand


	### The 'ls' command class.
	class LsCommand < RoninShell::Command
		command :ls

		### Run the command.
		def run( options, target, *ignored )
			full_path = File.expand_path( target, Dir.pwd )
			Dir.chdir( full_path )
			self.cli.message( full_path )
		end

	end # RoninShell::LsCommand



end # module RoninShell

# vim: set nosta noet ts=4 sw=4:

