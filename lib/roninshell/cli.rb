#!/usr/bin/env ruby

require 'readline'
require 'termios'
require 'pty'

require 'roninshell'
require 'roninshell/mixins'
require 'roninshell/constants'
require 'roninshell/exceptions'

# 
# The command-line interpreter for the Ronin Shell.
# 
# == Authors
# 
# * Michael Granger <ged@FaerieMUD.org>
# 
# :include: LICENSE
#
#--
#
# Please see the file LICENSE in the base directory for licensing details.
#
class RoninShell::CLI
	include RoninShell::Constants,
	        RoninShell::Loggable

	### Create a command-line interpreter with the specified +options+.
	def initialize( options )
		@startup_options = options
		@prompt = DEFAULT_PROMPT
		@quitting = false
	end


	######
	public
	######

	# The options struct the CLI was created with.
	attr_reader :startup_options


	### Run the shell interpreter with the specified +args.
	def run( *args )

		# Run until something sets the quit flag
		until @quitting
			input = Readline.readline( @prompt, true )
			self.log.debug "Input is: %p" % [ input ]

			# EOL makes the shell quit
			if input.nil?
				self.log.debug "EOL: setting quit flag"
				@quitting = true

			# Blank input -- just reprompt
			elsif input == ''
				self.log.debug "No command. Re-displaying the prompt."

			# Parse everything else into command + everything else
			else
				self.log.debug "Dispatching input: %p" % [ input ]
				self.dispatch_command( input )
			end
		end

	end

	### Dispatch a command.
	def dispatch_command( input )
		$stderr.puts "Not implemented."
	end

end # class RoninShell::CLI


