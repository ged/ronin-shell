#!/usr/bin/env ruby

require 'logger'
require 'erb'

require 'roninshell'

# 
# A collection of text-formatting and IO utility functions.
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
module RoninShell


	# A collection of utility functions for use in the Ronin Shell.
	module UtilityFunctions
		include RoninShell::Constants

		###############
		module_function
		###############

		### Dump the specified +object+ to a file as YAML, invoke an editor on it, then undump the 
		### result. If the file has changed, return the updated object, else returns +nil+.
		def edit_in_yaml( object )
			yaml = object.to_yaml

			fn = Digest::SHA1.hexdigest( yaml )
			tf = Tempfile.new( fn )

			tf.print( yaml )
			tf.close

			new_yaml = edit( tf.path )

			if new_yaml == yaml
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


		### Open a pipe to a process running the given +cmd+ and call the given block with it.
		def pipeto( *cmd )
			$DEBUG = true

			cmd.flatten!
			self.log.info( "Opening a pipe to: ", cmd.collect {|part| part =~ /\s/ ? part.inspect : part} ) 
			if $dryrun
				$stderr.puts "(dry run mode)"
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
			# $stderr.puts "Returning ansicode for TERM = %p: %p" %
			# 	[ ENV['TERM'], attributes ]
			return '' unless /(?:vt10[03]|xterm(?:-color)?|linux|screen)/i =~ ENV['TERM']
			attributes = ANSI_ATTRIBUTES.values_at( *attributes ).compact.join(';')

			# $stderr.puts "  attr is: %p" % [attributes]
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
					$stderr.puts( failure_msg + "\n\n" )
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
					$stderr.puts( failure_msg + "\n\n" )
					response = nil
				end
			end while response.nil?

			return nil if response == '~'
			return response
		end


		### Prompt for an array of values
		def prompt_for_multiple_values( label, default=nil )
		    $stderr.puts( MULTILINE_PROMPT % [label] )
		    if default
				$stderr.puts "Enter a single blank line to keep the default:\n  %p" % [ default ]
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


		### Return the specified +entries+ as an Array of span-sorted columns fit to the
		### current terminal width.
		def columnize( *entries )
			return Columnize.columnize( entries.flatten, @columns, '  ' )
		end

	end # module UtilityFunctions


	# 
	# A alternate formatter for Logger instances.
	# 
	# == Usage
	# 
	#   require 'roninshell/utilities'
	#   RoninShell.logger.formatter = RoninShell::LogFormatter.new( RoninShell.logger )
	# 
	# == Version
	#
	#  $Id$
	#
	# == Authors
	#
	# * Michael Granger <ged@FaerieMUD.org>
	#
	# :include: LICENSE
	#
	#--
	#
	# Please see the file LICENSE in the 'docs' directory for licensing details.
	#
	class LogFormatter < Logger::Formatter

		# The format to output unless debugging is turned on
		DEFAULT_FORMAT = "[%1$s.%2$06d %3$d/%4$s] %5$5s -- %7$s\n"

		# The format to output if debugging is turned on
		DEFAULT_DEBUG_FORMAT = "[%1$s.%2$06d %3$d/%4$s] %5$5s {%6$s} -- %7$s\n"


		### Initialize the formatter with a reference to the logger so it can check for log level.
		def initialize( logger, format=DEFAULT_FORMAT, debug=DEFAULT_DEBUG_FORMAT ) # :notnew:
			@logger       = logger
			@format       = format
			@debug_format = debug

			super()
		end

		######
		public
		######

		# The Logger object associated with the formatter
		attr_accessor :logger

		# The logging format string
		attr_accessor :format

		# The logging format string that's used when outputting in debug mode
		attr_accessor :debug_format


		### Log using either the DEBUG_FORMAT if the associated logger is at ::DEBUG level or
		### using FORMAT if it's anything less verbose.
		def call( severity, time, progname, msg )
			args = [
				time.strftime( '%Y-%m-%d %H:%M:%S' ),                         # %1$s
				time.usec,                                                    # %2$d
				Process.pid,                                                  # %3$d
				Thread.current == Thread.main ? 'main' : Thread.object_id,    # %4$s
				severity,                                                     # %5$s
				progname,                                                     # %6$s
				msg                                                           # %7$s
			]

			if @logger.level == Logger::DEBUG
				return self.debug_format % args
			else
				return self.format % args
			end
		end
	end # class LogFormatter


	# 
	# An alternate formatter for Logger instances that outputs +div+ HTML
	# fragments.
	# 
	# == Usage
	# 
	#   require 'treequel/utils'
	#   RoninShell.logger.formatter = RoninShell::HtmlLogFormatter.new( RoninShell.logger )
	# 
	# == Version
	#
	#  $Id$
	#
	# == Authors
	#
	# * Michael Granger <ged@FaerieMUD.org>
	#
	# :include: LICENSE
	#
	#--
	#
	# Please see the file LICENSE in the 'docs' directory for licensing details.
	#
	class HtmlLogFormatter < Logger::Formatter
		include ERB::Util  # for html_escape()

		# The default HTML fragment that'll be used as the template for each log message.
		HTML_LOG_FORMAT = %q{
		<div class="log-message %5$s">
			<span class="log-time">%1$s.%2$06d</span>
			[
				<span class="log-pid">%3$d</span>
				/
				<span class="log-tid">%4$s</span>
			]
			<span class="log-level">%5$s</span>
			:
			<span class="log-name">%6$s</span>
			<span class="log-message-text">%7$s</span>
		</div>
		}

		### Override the logging formats with ones that generate HTML fragments
		def initialize( logger, format=HTML_LOG_FORMAT ) # :notnew:
			@logger = logger
			@format = format
			super()
		end


		######
		public
		######

		# The HTML fragment that will be used as a format() string for the log
		attr_accessor :format


		### Return a log message composed out of the arguments formatted using the
		### formatter's format string
		def call( severity, time, progname, msg )
			args = [
				time.strftime( '%Y-%m-%d %H:%M:%S' ),                         # %1$s
				time.usec,                                                    # %2$d
				Process.pid,                                                  # %3$d
				Thread.current == Thread.main ? 'main' : Thread.object_id,    # %4$s
				severity.downcase,                                                     # %5$s
				progname,                                                     # %6$s
				html_escape( msg ).gsub(/\n/, '<br />')                       # %7$s
			]

			return self.format % args
		end

	end # class HtmlLogFormatter


end # module RoninShell


