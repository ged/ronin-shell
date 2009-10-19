#!/usr/bin/env ruby
# encoding: utf-8

require 'optparse'
require 'ostruct'

# 
# The Ronin Shell
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

	# Library version
	VERSION = '1.0.0'

	# VCS revision
	REVISION = %q$rev$

	### Make a vector out of the given +version_string+, which makes it easier to compare 
	### with other x.y.z-style version strings.
	def vvec( version_string )
		return version_string.split('.').collect {|v| v.to_i }.pack( 'N*' )
	end
	module_function :vvec

	unless vvec(RUBY_VERSION) >= vvec('1.9.1')
		raise "済みません！RoninShell requires Ruby 1.9.1 or greater."
	end

	# Load the logformatters and some other stuff first
	require 'roninshell/constants'
	require 'roninshell/utilities'

	include RoninShell::Constants

	### Logging
	@default_logger = Logger.new( $stderr )
	@default_logger.level = $DEBUG ? Logger::DEBUG : Logger::WARN

	@default_log_formatter = RoninShell::LogFormatter.new( @default_logger )
	@default_logger.formatter = @default_log_formatter

	@logger = @default_logger


	class << self
		# The log formatter that will be used when the logging subsystem is reset
		attr_accessor :default_log_formatter

		# The logger that will be used when the logging subsystem is reset
		attr_accessor :default_logger

		# The logger that's currently in effect
		attr_accessor :logger
		alias_method :log, :logger
		alias_method :log=, :logger=
	end


	### Reset the global logger object to the default
	def self::reset_logger
		self.logger = self.default_logger
		self.logger.level = Logger::WARN
		self.logger.formatter = self.default_log_formatter
	end


	### Returns +true+ if the global logger has not been set to something other than
	### the default one.
	def self::using_default_logger?
		return self.logger == self.default_logger
	end


	### Return the library's version string
	def self::version_string( include_buildnum=false )
		vstring = "%s %s" % [ self.name, VERSION ]
		vstring << " (build %s)" % [ REVISION ] if include_buildnum
		return vstring
	end

	# Now load the rest of the classes
	require 'roninshell/mixins'
	require 'roninshell/exceptions'
	require 'roninshell/cli'


	###############
	module_function
	###############

	### The main entrypoint to the shell.
	def start( arguments )
		options, cli_args = *self.parse_options( arguments )
		RoninShell.logger.debug "Options are: %p, arguments: %p" % [ options, cli_args ]
		cli = RoninShell::CLI.new( options )
		cli.run( *cli_args )
	end


	### Return the shell's default options as an OpenStruct object.
	def default_options
		options = OpenStruct.new({
			:command  => nil,
			:loglevel => :warn,
		})

		return options
	end


	### Parse the options from the given +arguments, returning an OpenStruct that describes them
	### and the remaining +arguments+.
	def parse_options( arguments )
		options = self.default_options

		@option_parser = OptionParser.new do |config|
			script_name = File.basename( $0 )

			config.set_summary_indent('  ')
			config.banner = "Usage: #{script_name} [OPTIONS]"
			config.define_head( DESCRIPTION )
			config.separator ''

			config.separator 'Execution'
			config.on( '-c STRING', String, 'Read commands from the specified STRING.' ) do |string|
				options.command = string
			end
			config.separator ''

			config.separator 'Runtime Options'
			config.on( '--debug', '-d', FalseClass, "Turn debugging on" ) do
				$DEBUG = true
				$trace = true
				RoninShell.logger.level = Logger::DEBUG
				options.loglevel = :debug
			end
			config.on_tail( '-v', '--version', 'Print the version and quit.' ) { puts VERSION; exit }
			config.on_tail( '-h', '--help', 'Show this help message.') { puts config; exit }
		end

		remainder = @option_parser.parse!( arguments )
		return options, remainder
	end


end # module RoninShell


