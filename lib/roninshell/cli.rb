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

	@@option_parsers = {}

	### Create a command-line interpreter with the specified +options+.
	def initialize( options )
		@startup_options = options
		@prompt          = DEFAULT_PROMPT
		@quit            = false
		@columns         = TermInfo.screen_width
		@rows            = TermInfo.screen_height

		@commands      = self.find_commands
		@completions   = @commands.abbrev
		@command_table = make_command_table( @commands )
	end


	######
	public
	######

	# The options struct the CLI was created with.
	attr_reader :startup_options


	### Run the shell interpreter with the specified +args.
	def run( *args )

		self.setup_completion
		self.read_history

		# Run until something sets the quit flag
		until @quit
			input = Readline.readline( @prompt, true )
			self.log.debug "Input is: %p" % [ input ]

			# EOL makes the shell quit
			if input.nil?
				self.log.debug "EOL: setting quit flag"
				@quit = true

			# Blank input -- just reprompt
			elsif input == ''
				self.log.debug "No command. Re-displaying the prompt."

			# Act on everything else
			else
				self.log.debug "Dispatching input: %p" % [ input ]
				self.dispatch_command( input )
			end
		end

		self.save_history

	end

	### Dispatch a command.
	def dispatch_command( input )
		command, *args = Shellwords.shellwords( input )

		# If it's a builtin command, run it
		if meth = @command_table[ command ]
			self.invoke_builtin_command( meth, args )

		# ...search the $PATH for it
		elsif path = which( command )
			self.invoke_path_command( path, *args )

		# ...otherwise call the fallback handler
		else
			self.handle_missing_command( command )
		end

	rescue => err
		self.log.error "%s: %s" % [ err.class.name, err.message ]
		self.log.debug { '  ' + err.backtrace.join("\n  ") }

		error_message( err.message )
	end


	### Invoke a builtin +command+ (a Method object) with the given +args+.
	def invoke_builtin_command( command, args )
		full_command = @completions[ command ].to_sym

		# If there's a registered optionparser for the command, use it to 
		# split out options and arguments, then pass those to the command.
		if @@option_parsers.key?( full_command )
			oparser, options = @@option_parsers[ full_command ]
			self.log.debug "Got an option-parser for #{full_command}."

			cmdargs = oparser.parse( args )
			self.log.debug "  options=%p, args=%p" % [ options, cmdargs ]
			meth.call( options, *cmdargs )

			options.clear

		# ...otherwise just call it with all the args.
		else
			meth.call( *args )
		end
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


	### Show help text for the specified command, or a list of all available commands 
	### if none is specified.
	def help_command( *args )
		if args.empty?
			$stderr.puts
			message colorize( "Available commands", :bold, :white ),
				*columnize(@commands)
		else
			cmd = args.shift.to_sym
			if @@option_parsers.key?( cmd )
				oparser, _ = @@option_parsers[ cmd ]
				self.log.debug "Setting summary width to: %p" % [ @columns ]
				oparser.summary_width = @columns
				output = oparser.to_s.sub( /^(.*?)\n/ ) do |match|
					colorize( :bold, :white ) { match }
				end

				$stderr.puts
				message( output )
			else
				error_message( "No help for '#{cmd}'" )
			end
		end
	end


	### Quit the shell.
	def quit_command( *args )
		message "Okay, exiting."
		@quit = true
	end





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
			possible_completions = @commands.grep( /^#{Regexp.quote(input)}/ ).sort
			self.log.debug "  possible completions: %p" % [ possible_completions ]
			return possible_completions
		else
			incomplete = parts.pop
			possible_completions = @currbranch.children.
				collect {|br| br.rdn }.grep( /^#{Regexp.quote(incomplete)}/ ).sort

			return possible_completions.map do |lastpart|
				parts.join( ' ' ) + ' ' + lastpart
			end
		end
	end


	### Find methods that implement commands and return them in a sorted Array.
	def find_commands
		return self.public_methods.
			collect {|mname| mname.to_s }.
			grep( /^(\w+)_command$/ ).
			collect {|mname| mname[/^(\w+)_command$/, 1] }.
			sort
	end


	### Handle a command that doesn't map to a builtin or an executable in the $PATH
	def handle_missing_command( command )
		error_message "#$0: #{command}: command not found"
	end


	#######
	private
	#######

	### Dump the specified +object+ to a file as YAML, invoke an editor on it, then undump the 
	### result. If the file has changed, return the updated object, else returns +nil+.
	def edit_in_yaml( object )
		yaml = object.to_yaml

		fn = Digest::SHA1.hexdigest( yaml )
		tf = Tempfile.new( fn )

		# message "Object as YAML is: ", yaml
		tf.print( yaml )
		tf.close

		new_yaml = edit( tf.path )

		if new_yaml == yaml
			message "Unchanged."
			return nil
		else
			return YAML.load( new_yaml )
		end
	end


	### Create a command table that maps command abbreviations to the Method object that
	### implements it.
	def make_command_table( commands )
		table = commands.abbrev
		table.keys.each do |abbrev|
			mname = table.delete( abbrev )
			table[ abbrev ] = self.method( mname + '_command' )
		end

		return table
	end


	### Return the specified args as a string, quoting any that have a space.
	def quotelist( *args )
		return args.flatten.collect {|part| part =~ /\s/ ? part.inspect : part}
	end


	### Run the specified command +cmd+ with system(), failing if the execution
	### fails.
	def run_command( *cmd )
		cmd.flatten!

		if cmd.length > 1
			self.log.debug( quotelist(*cmd) )
		else
			self.log.debug( cmd )
		end

		if $dryrun
			self.log.error "(dry run mode)"
		else
			system( *cmd )
			unless $?.success?
				raise "Command failed: [%s]" % [cmd.join(' ')]
			end
		end
	end


	### Run the given +cmd+ with the specified +args+ without interpolation by the shell and
	### return anything written to its STDOUT.
	def read_command_output( cmd, *args )
		self.log.debug "Reading output from: %s" % [ cmd, quotelist(cmd, *args) ]
		output = IO.read( '|-' ) or exec cmd, *args
		return output
	end


	### Run a subordinate Rake process with the same options and the specified +targets+.
	def rake( *targets )
		opts = ARGV.select {|arg| arg[0,1] == '-' }
		args = opts + targets.map {|t| t.to_s }
		run 'rake', '-N', *args
	end


	### Open a pipe to a process running the given +cmd+ and call the given block with it.
	def pipeto( *cmd )
		$DEBUG = true

		cmd.flatten!
		self.log.info( "Opening a pipe to: ", cmd.collect {|part| part =~ /\s/ ? part.inspect : part} ) 
		if $dryrun
			message "(dry run mode)"
		else
			open( '|-', 'w+' ) do |io|

				# Parent
				if io
					yield( io )

				# Child
				else
					exec( *cmd )
					raise "Command failed: [%s]" % [cmd.join(' ')]
				end
			end
		end
	end


	### Return the fully-qualified path to the specified +program+ in the PATH.
	def which( program )
		ENV['PATH'].split(/:/).
			collect {|dir| Pathname.new(dir) + program }.
			find {|path| path.exist? && path.executable? }
	end


	### Create a string that contains the ANSI codes specified and return it
	def ansi_code( *attributes )
		attributes.flatten!
		attributes.collect! {|at| at.to_s }
		# message "Returning ansicode for TERM = %p: %p" %
		# 	[ ENV['TERM'], attributes ]
		return '' unless /(?:vt10[03]|xterm(?:-color)?|linux|screen)/i =~ ENV['TERM']
		attributes = ANSI_ATTRIBUTES.values_at( *attributes ).compact.join(';')

		# message "  attr is: %p" % [attributes]
		if attributes.empty? 
			return ''
		else
			return "\e[%sm" % attributes
		end
	end


	### Colorize the given +string+ with the specified +attributes+ and return it, handling 
	### line-endings, color reset, etc.
	def colorize( *args )
		string = ''

		if block_given?
			string = yield
		else
			string = args.shift
		end

		ending = string[/(\s)$/] || ''
		string = string.rstrip

		return ansi_code( args.flatten ) + string + ansi_code( 'reset' ) + ending
	end


	### Output the specified message +parts+.
	def message( *parts )
		$stderr.puts( *parts )
	end


	### Output the specified <tt>msg</tt> as an ANSI-colored error message
	### (white on red).
	def error_message( msg, details='' )
		$stderr.puts colorize( 'bold', 'white', 'on_red' ) { msg } + ' ' + details
	end
	alias :error :error_message


	### Highlight and embed a prompt control character in the given +string+ and return it.
	def make_prompt_string( string )
		return CLEAR_CURRENT_LINE + colorize( 'bold', 'yellow' ) { string + ' ' }
	end


	### Output the specified <tt>prompt_string</tt> as a prompt (in green) and
	### return the user's input with leading and trailing spaces removed.  If a
	### test is provided, the prompt will repeat until the test returns true.
	### An optional failure message can also be passed in.
	def prompt( prompt_string, failure_msg="Try again." ) # :yields: response
		prompt_string.chomp!
		prompt_string << ":" unless /\W$/.match( prompt_string )
		response = nil

		begin
			prompt = make_prompt_string( prompt_string )
			response = readline( prompt ) || ''
			response.strip!
			if block_given? && ! yield( response ) 
				error_message( failure_msg + "\n\n" )
				response = nil
			end
		end while response.nil?

		return response
	end


	### Prompt the user with the given <tt>prompt_string</tt> via #prompt,
	### substituting the given <tt>default</tt> if the user doesn't input
	### anything.  If a test is provided, the prompt will repeat until the test
	### returns true.  An optional failure message can also be passed in.
	def prompt_with_default( prompt_string, default, failure_msg="Try again." )
		response = nil

		begin
			default ||= '~'
			response = prompt( "%s [%s]" % [ prompt_string, default ] )
			response = default.to_s if !response.nil? && response.empty? 

			self.log.debug "Validating response %p" % [ response ]

			# the block is a validator.  We need to make sure that the user didn't
			# enter '~', because if they did, it's nil and we should move on.  If
			# they didn't, then call the block.
			if block_given? && response != '~' && ! yield( response )
				error_message( failure_msg + "\n\n" )
				response = nil
			end
		end while response.nil?

		return nil if response == '~'
		return response
	end


	### Prompt for an array of values
	def prompt_for_multiple_values( label, default=nil )
	    message( MULTILINE_PROMPT % [label] )
	    if default
			message "Enter a single blank line to keep the default:\n  %p" % [ default ]
		end

	    results = []
	    result = nil

	    begin
	        result = readline( make_prompt_string("> ") )
			if result.nil? || result.empty?
				results << default if default && results.empty?
			else
	        	results << result 
			end
	    end until result.nil? || result.empty?

	    return results.flatten
	end


	### Turn echo and masking of input on/off. 
	def noecho( masked=false )
		rval = nil
		term = Termios.getattr( $stdin )

		begin
			newt = term.dup
			newt.c_lflag &= ~Termios::ECHO
			newt.c_lflag &= ~Termios::ICANON if masked

			Termios.tcsetattr( $stdin, Termios::TCSANOW, newt )

			rval = yield
		ensure
			Termios.tcsetattr( $stdin, Termios::TCSANOW, term )
		end

		return rval
	end


	### Prompt the user for her password, turning off echo if the 'termios' module is
	### available.
	def prompt_for_password( prompt="Password: " )
		rval = nil
		noecho( true ) do
			$stderr.print( prompt )
			rval = ($stdin.gets || '').chomp
		end
		$stderr.puts
		return rval
	end


	### Display a description of a potentially-dangerous task, and prompt
	### for confirmation. If the user answers with anything that begins
	### with 'y', yield to the block. If +abort_on_decline+ is +true+,
	### any non-'y' answer will fail with an error message.
	def ask_for_confirmation( description, abort_on_decline=true )
		puts description

		answer = prompt_with_default( "Continue?", 'n' ) do |input|
			input =~ /^[yn]/i
		end

		if answer =~ /^y/i
			return yield
		elsif abort_on_decline
			error "Aborted."
			fail
		end

		return false
	end
	alias :prompt_for_confirmation :ask_for_confirmation


	### Search line-by-line in the specified +file+ for the given +regexp+, returning the
	### first match, or nil if no match was found. If the +regexp+ has any capture groups,
	### those will be returned in an Array, else the whole matching line is returned.
	def find_pattern_in_file( regexp, file )
		rval = nil

		File.open( file, 'r' ).each do |line|
			if (( match = regexp.match(line) ))
				rval = match.captures.empty? ? match[0] : match.captures
				break
			end
		end

		return rval
	end


	### Search line-by-line in the output of the specified +cmd+ for the given +regexp+,
	### returning the first match, or nil if no match was found. If the +regexp+ has any 
	### capture groups, those will be returned in an Array, else the whole matching line
	### is returned.
	def find_pattern_in_pipe( regexp, *cmd )
		output = []

		self.log.info( cmd.collect {|part| part =~ /\s/ ? part.inspect : part} ) 
		Open3.popen3( *cmd ) do |stdin, stdout, stderr|
			stdin.close

			output << stdout.gets until stdout.eof?
			output << stderr.gets until stderr.eof?
		end

		result = output.find { |line| regexp.match(line) } 
		return $1 || result
	end


	### Invoke the user's editor on the given +filename+ and return the exit code
	### from doing so.
	def edit( filename )
		editor = ENV['EDITOR'] || ENV['VISUAL'] || DEFAULT_EDITOR
		system editor, filename.to_s
		unless $?.success? || editor =~ /vim/i
			raise "Editor exited with an error status (%d)" % [ $?.exitstatus ]
		end
		return File.read( filename )
	end


	### Make an easily-comparable version vector out of +ver+ and return it.
	def vvec( ver )
		return ver.split('.').collect {|char| char.to_i }.pack('N*')
	end


	### Return an ANSI-colored version of the given +rdn+ string.
	def format_rdn( rdn )
		rdn.split( /,/ ).collect do |rdn|
			key, val = rdn.split( /\s*=\s*/, 2 )
			colorize( :white ) { key } +
				colorize( :bold, :black ) { '=' } +
				colorize( :bold, :white ) { val }
		end.join( colorize(',', :green) )
	end


	### Highlight LDIF and return it.
	def format_ldif( ldif )
		return ldif.gsub( /^(\S[^:]*)(::?)\s*(.*)$/ ) do
			key, sep, val = $1, $2, $3
			case sep
			when '::'
				colorize( :cyan ) { key } + ':: ' + colorize( :dark, :white ) { val }
			when ':'
				colorize( :bold, :cyan ) { key } + ': ' + colorize( :dark, :white ) { val }
			else
				key + sep + ' ' + val
			end
		end
	end


	### Return the specified +entries+ as an Array of span-sorted columns fit to the
	### current terminal width.
	def columnize( *entries )
		return Columnize.columnize( entries.flatten, @columns, '  ' )
	end




end # class RoninShell::CLI


