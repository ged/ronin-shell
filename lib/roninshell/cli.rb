#!/usr/bin/env ruby

require 'abbrev'
require 'columnize'
require 'digest/sha1'
require 'logger'
require 'open3'
require 'optparse'
require 'pathname'
require 'pty'
require 'readline'
require 'shellwords'
require 'tempfile'
require 'termios'
require 'terminfo'
require 'yaml'

require 'roninshell'
require 'roninshell/mixins'
require 'roninshell/constants'
require 'roninshell/exceptions'
require 'roninshell/command'
require 'roninshell/command/builtins'

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
	        RoninShell::Loggable,
	        RoninShell::UtilityFunctions

	@@option_parsers = {}

	### Create a command-line interpreter with the specified +options+.
	def initialize( options )
		@startup_options = options

		@prompt          = DEFAULT_PROMPT
		@aliases         = {}

		@columns         = TermInfo.screen_width
		@rows            = TermInfo.screen_height
		@commands        = RoninShell::Command.require_all
		@command_table   = self.make_command_table( @commands )

		@quitting        = false

		self.log.debug "%p: set up with %d builtin commands for a %dx%d terminal" %
			[ self.class, @commands.length, @columns, @rows ]
	end


	######
	public
	######

	# The options struct the CLI was created with.
	attr_reader :startup_options

	# Quit flag -- setting this to true will cause the shell to exit out of its input loop.
	attr_accessor :quitting

	# The loaded shell commands
	attr_reader :commands



	### Run the shell interpreter with the specified +args.
	def run( *args )

		self.setup_completion
		self.read_history

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

			# Act on everything else
			else
				self.log.debug "Dispatching input: %p" % [ input ]
				command, *args = Shellwords.shellwords( input )
				self.dispatch_command( command, *args )
			end
		end

		self.save_history

	end


	### Dispatch a command.
	def dispatch_command( command, *args )

		# If it's an alias, recurse 
		if actual = @aliases[ command ]
			self.log.debug "%s: Expanding alias to %p" % [ command, actual ]
			self.dispatch_command( actual, *args )

		# ...if it's a builtin command, run it
		elsif cmdobj = @command_table[ command ]
			self.log.debug "%s: Found %p in the command table" % [ command, cmdobj ]
			self.invoke_command( cmdobj, *args )

		# ...search the $PATH for it
		elsif path = which( command )
			self.log.debug "%s: Found %p in the PATH" % [ command, path ]
			self.invoke_path_command( path, *args )

		# ...otherwise call the fallback handler
		else
			self.log.debug "%s: Not found." % [ command ]
			self.handle_missing_command( command )
		end

	rescue => err
		self.log.error "%s: %s" % [ err.class.name, err.message ]
		self.log.debug { '  ' + err.backtrace.join("\n  ") }

		error_message( err.message )
	end


	### Invoke a command object with the given +args_and_options+.
	def invoke_command( command, *args_and_options )
		self.log.debug "Invoking %p with args and options: %p" % [ command, args_and_options ]
		# :TODO: Do option-parsing
		options, *args = command.parse_options( args_and_options )
		command.run( options, *args )
	end


	### Invoke a command from the $PATH after sanity checks.
	def invoke_path_command( path, *args )
		raise "#{path}: permission denied" unless path.executable?
		if pid = Process.fork
			Process.wait( pid )
		else
			exec( path.to_s, *args )
		end
	end


	### Output the specified message +parts+.
	def message( *parts )
		$stdout.puts( *parts )
	end


	### Output the specified <tt>msg</tt> as an ANSI-colored error message
	### (white on red).
	def error_message( msg, details='' )
		$stderr.puts colorize( 'bold', 'white', 'on_red' ) { msg } + ' ' + details
	end
	alias :error :error_message


	#########
	protected
	#########

	### Set up Readline completion
	def setup_completion
		Readline.completion_proc = self.method( :completion_callback ).to_proc
		Readline.completer_word_break_characters = ''
	end


	### Read command line history from HISTORY_FILE
	def read_history
		histfile = HISTORY_FILE.expand_path

		if histfile.exist?
			lines = histfile.readlines.collect {|line| line.chomp }
			self.log.debug "Read %d saved history commands from %s." % [ lines.length, histfile ]
			Readline::HISTORY.push( *lines )
		else
			self.log.debug "History file '%s' was empty or non-existant." % [ histfile ]
		end
	end


	### Save command line history to HISTORY_FILE
	def save_history
		histfile = HISTORY_FILE.expand_path

		lines = Readline::HISTORY.to_a.reverse.uniq.reverse
		lines = lines[ -DEFAULT_HISTORY_SIZE, DEFAULT_HISTORY_SIZE ] if
			lines.length > DEFAULT_HISTORY_SIZE

		self.log.debug "Saving %d history lines to %s." % [ lines.length, histfile ]

		histfile.open( File::WRONLY|File::CREAT|File::TRUNC ) do |ofh|
			ofh.puts( *lines )
		end
	end


	### Handle completion requests from Readline.
	def completion_callback( input )
		self.log.debug "Input completion: %p" % [ input ]
		parts = Shellwords.shellwords( input )

		# If there aren't any arguments, it's command completion
		if parts.length == 1
			# One completion means it's an unambiguous match, so just complete it.
			possible_completions = @command_table.keys.grep( /^#{Regexp.quote(input)}/ ).sort
			self.log.debug "  possible completions: %p" % [ possible_completions ]
			return possible_completions
		else
			incomplete = parts.pop
			self.log.warn "I don't yet do programmable or file completion."
			return []
		end
	end


	### Handle a command that doesn't map to a builtin or an executable in the $PATH
	def handle_missing_command( command )
		error_message "#$0: #{command}: command not found"
	end


	### Create a command table that maps command abbreviations to the Method object that
	### implements it.
	def make_command_table( command_classes )
		self.log.debug "Making a command table out of %d command classes" % [ command_classes.length ]

		# Map command classes to their canonical command
		table = command_classes.inject({}) {|hash,cmd| hash[ cmd.command.to_s ] = cmd.new( self ); hash }
		self.log.debug "  command table (without abbrevs) is: %p" % [ table ]

		# Now add abbreviations
		abbrevs = table.keys.abbrev
		abbrevs.keys.each do |abbrev|
			cmd = abbrevs[ abbrev ]
			self.log.debug "  mapping abbreviation %p to %p" % [ abbrev, table[cmd] ]
			table[ abbrev ] ||= table[ cmd ]
		end

		return table
	end


end # class RoninShell::CLI


