#!/usr/bin/env ruby
# encoding: utf-8

require 'pathname'

require 'roninshell'

# 
# A collection of constants for RoninShell classes.
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
module RoninShell::Constants

	# The description output in the usage message
	DESCRIPTION = "A masterless shell (浪人)."

	# The default prompt
	DEFAULT_PROMPT = '$> '

	# The name of the history file
	HISTORY_FILE = Pathname( '~/.ronin-history' )

	# The default number of lines to save in history
	DEFAULT_HISTORY_SIZE = 100

	# Set some ANSI escape code constants (Shamelessly stolen from Perl's
	# Term::ANSIColor by Russ Allbery <rra@stanford.edu> and Zenin <zenin@best.com>
	ANSI_ATTRIBUTES = {
		'clear'      => 0,
		'reset'      => 0,
		'bold'       => 1,
		'dark'       => 2,
		'underline'  => 4,
		'underscore' => 4,
		'blink'      => 5,
		'reverse'    => 7,
		'concealed'  => 8,

		'black'      => 30,   'on_black'   => 40,
		'red'        => 31,   'on_red'     => 41,
		'green'      => 32,   'on_green'   => 42,
		'yellow'     => 33,   'on_yellow'  => 43,
		'blue'       => 34,   'on_blue'    => 44,
		'magenta'    => 35,   'on_magenta' => 45,
		'cyan'       => 36,   'on_cyan'    => 46,
		'white'      => 37,   'on_white'   => 47
	}



end # module RoninShell::Constants
