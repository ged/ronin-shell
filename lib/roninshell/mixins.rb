#!/usr/bin/ruby

require 'logger'
require 'roninshell'


#--
# A collection of mixins shared between RoninShell classes. Stolen mostly from
# ThingFish and Treequel.
#
module RoninShell # :nodoc:

	# 
	# Add logging to a RoninShell class. Including classes get #log and #log_debug methods.
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
	# --
	#
	# Please see the file LICENSE in the 'docs' directory for licensing details.
	#
	module Loggable

		LEVEL = {
			:debug => Logger::DEBUG,
			:info  => Logger::INFO,
			:warn  => Logger::WARN,
			:error => Logger::ERROR,
			:fatal => Logger::FATAL,
		  }

		### A logging proxy class that wraps calls to the logger into calls that include
		### the name of the calling class.
		class ClassNameProxy # :nodoc:

			### Create a new proxy for the given +klass+.
			def initialize( klass, force_debug=false )
				@classname   = klass.name
				@force_debug = force_debug
			end

			### Delegate calls the global logger with the class name as the 'progname' 
			### argument.
			def method_missing( sym, msg=nil, &block )
				return super unless LEVEL.key?( sym )
				sym = :debug if @force_debug
				RoninShell.logger.add( LEVEL[sym], msg, @classname, &block )
			end
		end # ClassNameProxy

		#########
		protected
		#########

		### Copy constructor -- clear the original's log proxy.
		def initialize_copy( original )
			@log_proxy = @log_debug_proxy = nil
			super
		end

		### Return the proxied logger.
		def log
			@log_proxy ||= ClassNameProxy.new( self.class )
		end

		### Return a proxied "debug" logger that ignores other level specification.
		def log_debug
			@log_debug_proxy ||= ClassNameProxy.new( self.class, true )
		end
	end # module Loggable


end # module RoninShell

# vim: set nosta noet ts=4 sw=4:

