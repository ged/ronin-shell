#!/usr/bin/env ruby

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
	require 'roninshell/exceptions'

end # module RoninShell


