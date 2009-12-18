#!/usr/bin/ruby

require 'roninshell'
require 'roninshell/cli'
require 'roninshell/mixins'
require 'roninshell/exceptions'


# The base shell command class.
# 
# == Usage
# 
#   # yourneatolib/roninshell/commands.rb
#   require 'roninshell/command'
#   
#   class NeatoCommand < RoninShell::Command
#     name :neato
#     
#     def run( shell, *args )
#       return self.neato_object
#     end
#     
#   end
#   
class RoninShell::Command
	include RoninShell::Loggable

	# Command plugin loader 
	COMMAND_PLUGIN_LOADER = 'roninshell/commands'

	# Suffixes of files to try to load for commands -- stolen from RubyGems.
	COMMAND_SUFFIXES = ['', '.rb', '.rbw', '.so', '.bundle', '.dll', '.sl', '.jar']

	# Glob pattern for finding files that end in one of the COMMAND_SUFFIXES
	COMMAND_SUFFIX_PATTERN = '{' + COMMAND_SUFFIXES.join(',') + '}'


	#################################################################
	###	C L A S S   M E T H O D S
	#################################################################

	# Subclasses of RoninShell::Command
	@@subclasses = []

	# The command name
	@command = nil

	# OptionParser instance and option struct for this command
	@option_parser = nil

	# OpenStruct prototype
	@options = nil


	### Return the Array of all known subclasses.
	def self::subclasses
		return @@subclasses
	end


	### Inheritance callback -- track subclasses of Command for later instantiation.
	def self::inherited( subclass )
		RoninShell.logger.debug "Loaded %s (%s)" % [ subclass.name, subclass ]
		@@subclasses << subclass
		subclass.instance_variable_set( :@command, nil )
		super
	end


	### Search the $LOAD_PATH (and installed Gems, if Rubygems is loaded) for
	### files under COMMAND_LIB_PREFIX, loading each one in turn. Once they're all loaded,
	### return any resulting command classes.
	def self::require_all
		files = if defined?( Gem )
				Gem.find_files( COMMAND_PLUGIN_LOADER )
			else
				$LOAD_PATH.collect do |dir|
					pattern = File.expand_path(COMMAND_PLUGIN_LOADER, dir) + COMMAND_SUFFIX_PATTERN
					Dir[ pattern ].select do |path|
						File.file?( path.untaint )
					end
				end.flatten
			end

		require( *files ) unless files.empty?

		return self.subclasses
	end


	### Get/set the command name
	def self::command( newname=nil )
		@command = newname if newname
		return @command
	end


	### Create an option parser from the specified +block+ for the given +command+ and register
	### it. Many thanks to apeiros and dominikh on #Ruby-Pro for the ideas behind this.
	def self::set_options( command, &block )
	    ostruct = OpenStruct.new
		oparser = OptionParser.new( "Help for #{command}" ) do |o|
			yield( o, options )
		end
		oparser.default_argv = []

		self.option_parser = oparser
		self.options = ostruct
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new instance of the command for the given +cli+ instance.
	def initialize( cli )
		@cli = cli
	end


	######
	public
	######

	# The RoninShell::CLI instance this instance belongs to.
	attr_reader :cli


	### Return the name of the command.
	def command
		return self.class.command
	end


	### Virtual method -- you must override this method in your own command class.
	def run( options, *args )
		raise NotImplementedError, "%s does implement #run" % [ self.class.command ]
	end


end # class RoninShell::Command

# vim: set nosta noet ts=4 sw=4:

