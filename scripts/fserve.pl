#!/usr/bin/perl -w
#############################################################################
#
#	FServe - file server using DCC
#			 for Irssi 0.7.99
#
#	Copyright (C) 2001 Martin Persson
#
#	If you have any comments, bug reports or anything else
#	please contact me at mep@passagen.se
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#
#	Changelog 0.6.0
#	====================================================================
#
#	* Merged patch from Ethan Fischer (allanon@crystaltokyo.com)
#   	  - added ignore_chat option that, when turned on, ignores the
#    	    trigger if said in the channel; it also changes the trigger 
#   	    advertisement to "/ctcp nick !trigger"
#   	  - added ops_priority option that, when set to 1, force-adds 
#   	    requests from to the top of the download queue regardless of
#           queue size; when set to 2, it does the same thing for voices
#   	  - added log_name option to specify the name of a logfile which 
#           will be used to store transfer logs; the log contains the time 
#           a dcc transfer finishes, whether it finished or failed, filename,
#           nick, bytes sent, start time, and end time
#         - added a kludge to kill dcc chats after an "exit" in sig_timeout()
#   	  - added a -clear option to the set command (eg, /fs set -clear
#           log_name) which sets the variable to an empty string
#
#   	* Merged patch from Brian (btherl@optushome.com.au)
#         - Avoid division by zero when dcc send takes 0 time to complete
#   	  - new user command "read" - allows reading of small (<30k) files,
#           such as checksum files
#         - set line delimeter before load_config()
#   	  - formatting of function headers
#
#   	thanks for the patches guys :)
#
#   	* the bytecounter now also counts the number of bytes sent
#   	  for failed transfers as well as successful transfers
#         (with respects to resumed files)
#   	* some bugfixes I don't remember ;)
#
#############################################################################

use strict;
no strict 'refs';

use Irssi;
use Irssi::Irc;

my $version = "0.6.0";

#
#	Welcome & help messages
#

my @welcome_msg = (
	"ÛßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßÛ",
	"Û         -=[ FServe for Irssi 0.7.99 ]=-         Û",
	"ÛÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÛ",
	"Û                                                 Û",
	"Û   Commands: ls/dir get dequeue clr_queue queue  Û",
	"Û             read help sends who stats quit      Û",
	"Û                                                 Û",
	"Û             Type help for more info             Û",
	"Û                                                 Û",
	"ÛÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÛ"
);

my @help_msg = (
	"-=[ Available commands ]=-",
	"  ls / dir       - list files in current directory",
	"  get <file>     - inserts <file> into the queue",
	"  read <file>    - displays contents of <file>",
	"  dequeue <nr>   - removes file in slot <nr>",
	"  clr_queue[s]   - removes your queued files",
	"  queue[s]       - lists the queue",
	"  sends          - lists active sends",
	"  who            - lists users online",
	"  stats          - shows some statistice",
	"  quit           - closes the connection",
);

my @srv_help_msg = (
	"command - [params] description\003\n",
	"on      - [0] enables fileserver",
	"off     - [0] disables fileserver",
	"save    - [0] save config file",
	"load    - [0] load config file",
	"saveq   - [0] saves sends/queue",
	"loadq   - [0] loads the queue",
	"set     - [2] sets variables",
	"insert  - [2] inserts a file in queue",
	"move    - [2] moves queue slots around",
	"clear   - [1] removes queued files",
	"queue   - [0] lists file queue",
	"sends   - [0] lists active sends",
	"who     - [0] lists users online",
	"stats   - [0] shows server statistics",
	"recache - [0] updates filecache\003\n",
	"Usage: /fs <command> [<arguments>]",
	"For parameter info type /fs <cmd>",
);

###############################################################################
#	fileserver preferences (/fs set <var> <data>)
#	default values, feel free to change them
###############################################################################
my %fs_prefs = (
	max_users 	=> 5,
	max_sends 	=> 2,
	max_queue	=> 10,
	user_slots	=> 3,
	min_cps		=> 9728,
	idle_time	=> 120,
	max_time	=> 600,
	ignore_msg	=> 1,
	ignore_chat     => 1,
	ops_priority    => 0,

	notify_interval => 900,
	auto_save	=> 600,

    	log_name        => '',	
	trigger		=> '!dame',
	channels	=> '#linuxlatino',
	root_dir	=> '/tmp',
	note		=> '',
	logo		=> '',

	clr_txt		=> "\00314",
	clr_hi		=> "\00312",
	clr_file	=> "\00315",
	clr_dir		=> "\00312",
);

###############################################################################
#	fileserver statistics
###############################################################################
my %fs_stats = (
	record_cps	=> 0,
	rcps_nick	=> "",
	sends_ok	=> 0,			# sends succeeded
	sends_fail	=> 0,			# sends failed
	transfd		=> 0,			# total bytes transferred
	login_count	=> 0,			# total number of logins
);

my @fs_queue = ();
my @fs_sends = ();
my %fs_users = ();

###############################################################################
#	private variables, don't set to any values
###############################################################################
my $fs_debug = 0;
my $fs_enabled = 0; 	# always start disabled
my $online_time = 0;	# time since last script restart
my $timer_tag;
my $server_tag = "";
my %fs_cache = ();
my $logfp;
my @kill_dcc;

###############################################################################
#	setup signal handlers
###############################################################################
Irssi::signal_add_first('event privmsg', 'sig_event_privmsg');
Irssi::signal_add_first('default ctcp msg', 'sig_ctcp_msg');
Irssi::signal_add_last('dcc chat message', 'sig_dcc_msg');

Irssi::signal_add_last('dcc connected', 'sig_dcc_connected');
Irssi::signal_add('dcc destroyed', 'sig_dcc_destroyed');

Irssi::signal_add('nicklist changed', 'sig_nicklist_changed');
Irssi::signal_add('server disconnected', 'sig_server_disconnected');

Irssi::command_bind('fs', 'sig_fs_command');
print_msg("FServe version $version");
print_log("FServe starting up");

if (-e "$ENV{HOME}/.irssi/fserve.conf") {
	load_config();
} else {
	print_msg("You can configure the fileserver using the /fs command");
	print_msg("go through the variables (/fs set for list) and save the");
	print_msg("config file with /fs save");
}

###############################################################################
#	prints debug messages in the (fserve_dbg) window
###############################################################################
sub print_debug
{
	if ($fs_debug) {
		Irssi::print("$fs_prefs{logo} <DBG> @_");
	}
}

###############################################################################
#	prints server message in current window
###############################################################################
sub print_msg
{
	Irssi::active_win()->print("$fs_prefs{logo}$fs_prefs{clr_txt} @_");
}

###############################################################################
###############################################################################
##
##		Signal handler routines
##
###############################################################################
###############################################################################

###############################################################################
#	puts fileserver offline when irc server disconnects
###############################################################################
sub sig_server_disconnected
{
	my ($server) = @_;

	if ($fs_enabled && $server->{tag} == $server_tag) {
		$fs_enabled = 0;
		Irssi::timeout_remove($timer_tag);
		print_msg("Server disconnected, fileserver offline!");
	}
}

###############################################################################
#	updates some variables when DCC CHAT is established
###############################################################################
sub sig_dcc_connected
{
	my ($dcc) = @_;

	print_debug("DCC connected: $dcc->{type} $dcc->{nick}");
	if ($dcc->{type} eq "CHAT" && defined $fs_users{$dcc->{nick}}) {
		print_debug("User $dcc->{nick} connected!");
		$fs_users{$dcc->{nick}}{status} = 0;
		$fs_stats{login_count}++;

		foreach (@welcome_msg) {
			send_user_msg($dcc->{nick}, $_);
		}
	}
}

###############################################################################
#	cleanups after DCC CHAT/SEND disconnects
###############################################################################
sub sig_dcc_destroyed
{
	my ($dcc) = @_;

	print_debug("DCC destroyed: $dcc->{type} $dcc->{nick}");

	if ($dcc->{type} eq "CHAT" && defined $fs_users{$dcc->{nick}}) {
		delete $fs_users{$dcc->{nick}};
		print_debug("Users left: ".keys %fs_users);
	} elsif ($dcc->{type} eq "SEND") {
		foreach (0 .. $#fs_sends) {
			if ($fs_sends[$_]{nick} eq $dcc->{nick} &&
				$fs_sends[$_]{file} eq $dcc->{arg}) {
				if ($dcc->{transfd} == $fs_sends[$_]{size}) {
				    	print_log("dcc_finish $dcc->{arg} $dcc->{nick} ".
					    	"$dcc->{skipped} $dcc->{transfd} ".
						"$dcc->{starttime} ".time());
					$fs_stats{sends_ok}++;

					## Update speed record (if new)
					if (time() > $dcc->{starttime}) {
						my $speed = ($dcc->{transfd}-$dcc->{skipped})/
							 (time() - $dcc->{starttime});

					    if ($speed > $fs_stats{record_cps}) {
						    $fs_stats{record_cps} = $speed;
						    $fs_stats{rcps_nick} = $dcc->{nick};
					    }
					}
				} else {
					if (defined($fs_sends[$_]) && $fs_sends[$_]{transfd} == -1) {
					} else {
					    	print_log("dcc_fail $dcc->{arg} $dcc->{nick} ".
						    	"$dcc->{skipped} $dcc->{transfd} ".
							"$dcc->{starttime} ".time());
						$fs_stats{sends_fail}++;
					}
				}
				
				## Update bytes transferred
		    		$fs_stats{transfd} += ($dcc->{transfd} - $dcc->{skipped});
				
				splice(@fs_sends, $_, 1);
				print_debug("SEND closed to $dcc->{nick}, file: ".
					"$dcc->{arg}, transfd: $dcc->{transfd}");
				return;
			}
		}
	}
}

###############################################################################
#	handles dcc chat messages
###############################################################################
sub sig_dcc_msg
{
	my ($dcc, $msg) = @_;

	# ignore messages from unconnected dcc chats
	return unless ($fs_enabled && defined $fs_users{$dcc->{nick}});

	# reset idle time for user
	$fs_users{$dcc->{nick}}{status} = 0;
	
	my ($cmd, @args) = split(' ', $msg);
	
	if ($cmd eq "dir" || $cmd eq "ls") {
		list_dir($dcc->{nick}, "@args");
	} elsif ($cmd eq "cd") {
		change_dir($dcc->{nick}, "@args");
	} elsif ($cmd eq "cd..") { # darn windows users ;)
	    	change_dir($dcc->{nick}, '..');
	} elsif ($cmd eq "get") {
		queue_file($dcc->{nick}, "@args");
	} elsif ($cmd eq "dequeue") {
		dequeue_file($dcc->{nick}, $args[0]);
	} elsif ($cmd eq "clr_queue" || $cmd eq "clr_queues") {
		clear_queue($dcc->{nick}, 0);
	} elsif ($cmd eq "queue" || $cmd eq "queues") {
		display_queue($dcc->{nick});
	} elsif ($cmd eq "sends") {
		display_sends($dcc->{nick});
	} elsif ($cmd eq "who") {
		display_who($dcc->{nick});
	} elsif ($cmd eq "stats") {
		display_stats($dcc->{nick});
	} elsif ($cmd eq "read") {
		display_file($dcc->{nick}, $args[0]);
	} elsif ($cmd eq "help") {
		foreach (@help_msg) {
			send_user_msg($dcc->{nick}, $_);
		}
	} elsif ($cmd eq "exit" || $cmd eq "quit" || $cmd eq "bye") {
    	    	push(@kill_dcc, $dcc->{nick});
#		send_user_msg($dcc->{nick}, "Just close the chat!");
#		$dcc->{server}->command("/DCC CLOSE CHAT $dcc->{nick}");
#		Irssi::signal_stop();
	}
}


###############################################################################
#	handles ctcp messages
###############################################################################
sub sig_ctcp_msg
{
	my ($server, $args, $sender, $addr, $target) = @_;

	return if (!$fs_enabled || $server->{tag} != $server_tag);
	print_debug("CTCP from $sender: $args");

	if ($args eq uc($fs_prefs{trigger}) && user_in_channel($sender)) {
		if (defined($fs_users{$sender})) {
			if (!$fs_users{$sender}{ignore} && $fs_prefs{ignore_msg}) {
				$server->command("/NOTICE $sender $fs_prefs{clr_txt}".
					"A DCC chat offer has already been sent to you!");
			}

			$fs_users{$sender}{ignore} = 1;
			return;
		}

		if (keys(%fs_users) < $fs_prefs{max_users}) {
			initiate_dcc_chat($server, $sender);
		} else {
			$server->command("/NOTICE $sender $fs_prefs{clr_txt}".
					 "Sorry, server is full (".
					 $fs_prefs{clr_hi}.$fs_prefs{max_users}.
					 $fs_prefs{clr_txt}.")!");
		}

		Irssi::signal_stop();
	}
}


###############################################################################
#	handles channel and private messages
###############################################################################
sub sig_event_privmsg
{
	my ($server, $data, $sender, $addr) = @_;
	my ($target, $text) = split(/ :/, $data, 2);

	return if (!$fs_enabled || $server->{tag} != $server_tag);

	foreach my $channel (split(' ', $fs_prefs{channels})) {
		if ($channel eq $target) {
		    	if (!$fs_prefs{ignore_chat} && uc($text) eq uc($fs_prefs{trigger})) {
				if (defined($fs_users{$sender})) {
					if (!$fs_users{$sender}{ignore} && $fs_prefs{ignore_msg}) {
						$server->command("/NOTICE $sender $fs_prefs{clr_txt}".
							"A DCC chat offer has already been sent to you!");
					}

					$fs_users{$sender}{ignore} = 1;
					return;
				}

				if (keys(%fs_users) < $fs_prefs{max_users}) {
					initiate_dcc_chat($server, $sender);
				} else {
					$server->command("/NOTICE $sender ".
						 $fs_prefs{clr_txt}.
						 "Sorry, server is full (".
						 $fs_prefs{clr_hi}.
						 $fs_prefs{max_users}.
						 $fs_prefs{clr_txt}.")!");
				}
			}
			if (uc($text) eq '!LIST') {
				show_notice($sender);
			}
		}
	}
	
	# kill connections that said "bye"
	foreach (@kill_dcc) {
	    $server->command("/DCC CLOSE CHAT $_");
	}
	@kill_dcc = ();
}


###############################################################################
#	updates userinfo on nick changes
###############################################################################
sub sig_nicklist_changed
{
	my ($chan, $nick, $oldnick) = @_;
	my $ch_ok = 0;

	foreach (split(' ', $fs_prefs{channels})) {
		if ($_ eq $chan->{name}) {
			$ch_ok = 1;
			last;
		}	
	}

	print_debug("NICK CHANGE: $oldnick -> $nick->{nick} on $chan->{name}");
	if ($ch_ok && defined $fs_users{$oldnick}) {
		# update user data
		my %rec = %{ $fs_users{$oldnick} };
		delete $fs_users{$oldnick};
		$fs_users{$nick->{nick}} = { %rec };
		
		# update queue
		foreach (0 .. $#fs_queue) {
			if ($fs_queue[$_]{nick} eq $oldnick) {
				$fs_queue[$_]{nick} = $nick->{nick};
			}
		}
	}
}

###############################################################################
#	sig_timeout():	called once every second
###############################################################################
sub sig_timeout
{
	my $server = Irssi::server_find_tag($server_tag);
	if (!$server || !$server->{connected}) {
		print_msg("Error: this should never happen!!!");
		return;
	}

	# check for campers...
	foreach (keys %fs_users) {
		if ($fs_users{$_}{status} >= 0) {
			$fs_users{$_}{status}++;
			$fs_users{$_}{time}++;

			if ($fs_users{$_}{status} > $fs_prefs{idle_time}) {
				send_user_msg($_, "Idletime ($fs_prefs{clr_hi}".
							  "$fs_prefs{idle_time}$fs_prefs{clr_txt} sec) ".
							  "reached, disconnecting!");
				$server->command("/DCC CLOSE CHAT $_");
			} elsif ($fs_users{$_}{time} > $fs_prefs{max_time}) {
				send_user_msg($_, "Does this look like a campingsite? (".
							  "$fs_prefs{clr_hi}$fs_prefs{max_time} ".
							  "sec$fs_prefs{clr_txt})");
				$server->command("/DCC CLOSE CHAT $_");
			}
		}
	}

	# notify channels, send files...
	if ($fs_enabled) {
		$online_time++;

		# auto save config file
		if ($fs_prefs{auto_save} && time() % $fs_prefs{auto_save} == 0) {
			print_msg("Autosaving...");
			save_config();
			save_queue();
		}

		# check if there are files to send
		while (@fs_sends < $fs_prefs{max_sends} && @fs_queue > 0) {
			if (send_next_file($server)) {
				last;
			}
		}

		# notify channels
		if ($fs_prefs{notify_interval} && 
			time() % $fs_prefs{notify_interval} == 0) {
			foreach (split(' ', $fs_prefs{channels})) {
				show_notice($_);
			}
		}

		# check speed of sends
		if ($fs_prefs{min_cps} && time() % 60 == 0) {
			for (my $s = $#fs_sends; $s >= 0; $s--) {
				check_send_speed($s);
			}
		}
	}
}

###############################################################################
#	check_send_speed(): aborts send in $slot if speed < $fs_prefs{min_cps}
###############################################################################
sub check_send_speed
{
	my ($s) = @_;

	foreach my $dcc (Irssi::Irc::dccs()) {
		if ($dcc->{type} eq 'SEND' && $dcc->{nick} eq $fs_sends[$s]{nick} &&
			$dcc->{arg} eq $fs_sends[$s]{file} && $dcc->{starttime}) {
			
			if (defined $fs_sends[$s]{transfd}) {
				my $speed = ($dcc->{transfd}-$fs_sends[$s]{transfd})/60;

				if ($speed < $fs_prefs{min_cps}) {
					$dcc->{server}->command("/NOTICE $fs_sends[$s]{nick} ".
						$fs_prefs{clr_txt}."The speed of your send (".
						$fs_prefs{clr_hi}.size_to_str($speed)."/s".
						$fs_prefs{clr_txt}.") is less than min CPS ".
						"requirement (".$fs_prefs{clr_hi}.
						size_to_str($fs_prefs{min_cps})."/s".
						$fs_prefs{clr_txt}."), aborting...");

					$fs_sends[$s]{transfd} = -1;
					$dcc->{server}->command("/DCC CLOSE SEND $dcc->{nick}");
					return;
				}
			}

			$fs_sends[$s]{transfd} = $dcc->{transfd};
			return;
		}
	}
}

##############################################################################
# Handle an "/fs *" type command
###############################################################################
sub sig_fs_command
{
	my ($cmd_line, $server, $win_item) = @_;
	my @args = split(' ', $cmd_line);

	if (@args <= 0 || lc($args[0]) eq 'help') {
		print_msg("-=[ $fs_prefs{clr_hi}Available commands$fs_prefs{clr_txt} ]=-");
		foreach (@srv_help_msg) {
			print_msg($_);
		}
		return;
	}

	# convert command to lowercase
	my $cmd = lc(shift(@args));

	if ($cmd eq 'on') {
		unless ($fs_enabled) {
			if (!$server || !$server->{connected}) {
				print_msg("Connect to a server first!");
				return;
			}

			update_files();
			$timer_tag = Irssi::timeout_add(1000, 'sig_timeout', 0);
			$server_tag = $server->{tag};
			$fs_enabled = 1;
		}
		print_msg("Fileserver online! (server: $server_tag)");
	} elsif ($cmd eq 'off') {
		if ($fs_enabled) {
			$fs_enabled = 0;
			Irssi::timeout_remove($timer_tag);
		}
		print_msg("Fileserver offline!");
	} elsif ($cmd eq 'set') {
		if (@args == 0) {
			print_msg("[$fs_prefs{clr_hi}FServe Variables$fs_prefs{clr_txt}]");
			foreach (sort(keys %fs_prefs)) {
				if (/clr/) {
					print_msg("$_ $fs_prefs{clr_hi}=$fs_prefs{clr_txt} ".
							  "$fs_prefs{$_}COLOR");
				} else {
					print_msg("$_ $fs_prefs{clr_hi}=$fs_prefs{clr_txt} ".
							  $fs_prefs{$_});
				}
			}
			print_msg("\003\n$fs_prefs{clr_txt}Ex: /fs set max_users 4");
		} elsif (@args < 2) {
			print_msg("Error: usage /fs set <var> <value>");
	    	} elsif ($args[0] eq '-clear' && defined $fs_prefs{$args[1]}) {
		    	print_msg("Clearing $args[1]");
			$fs_prefs{$args[1]} = "";
			if ($args[1] eq 'log_name' && $logfp) {
			    print_log("Closing log.");
			    close($logfp);
			    undef $logfp;
			}
		} elsif (defined $fs_prefs{$args[0]}) {
			my $var = shift(@args);
			$fs_prefs{$var} = "@args";
			if ($var =~ /^clr/) {
				print_msg("Setting: $var $fs_prefs{clr_hi}=$fs_prefs{$var}COLOR");
			} else {
				print_msg("Setting: $var $fs_prefs{clr_hi}=$fs_prefs{clr_txt} ".
						  $fs_prefs{$var});
			}
			if ($var eq 'log_name') {
			    if ($logfp) {
			    	print_log("Closing log.");
				close($logfp);
				undef $logfp;
			    }
			    print_log("Opening log.");
			}
		} else {
			print_msg("Error: unknown variable ($args[0])");
		}
	} elsif ($cmd eq 'save') {
		print_msg("Config file saved!") if (!save_config());
	} elsif ($cmd eq 'load') {
		print_msg("Config file loaded!") if (!load_config());
	} elsif ($cmd eq 'saveq') {
		print_msg("Sends & Queue saved!") if (!save_queue());
	} elsif ($cmd eq 'loadq') {
		print_msg("Queue loaded!") if (!load_queue());
	} elsif ($cmd eq 'who') {
		display_who('!fserve!');
	} elsif ($cmd eq 'recache') {
		update_files();
	} elsif ($cmd eq 'queue') {
		display_queue('!fserve!');
	} elsif ($cmd eq 'sends') {
		display_sends('!fserve!');
	} elsif ($cmd eq 'stats') {
		display_stats('!fserve!');
	} elsif ($cmd eq 'insert') {
		if (@args < 2) {
			print_msg("Usage /fs insert <nick> <file>");
			return;
		}
		my $nick = shift(@args);
		srv_queue_file($nick, "@args");
	} elsif ($cmd eq 'move') {
		if (@args < 2) {
			print_msg("Usage /fs move <from> <to>");
			return;
		}
		srv_move_slot($args[0], $args[1]);
	} elsif ($cmd eq 'clear') {
		if (@args < 1) {
			print_msg("Usage /fs clear <nick> | /fs clear -all");
			return;
		}
		if ($args[0] eq '-all') {
			@fs_queue = ();
		} else {
			clear_queue($args[0], 1);
		}
	} elsif ($cmd eq 'notify') {
		if ($fs_enabled) {
			foreach (split(' ', $fs_prefs{channels})) {
				show_notice($_);
			}
		} else {
			print_msg("Enable the fileserver first!");
		}
	}
}

###############################################################################
###############################################################################
##	
##		Script subroutines
##
###############################################################################
###############################################################################

###############################################################################
#	initiate_dcc_chat($server, $nick): inits a dcc chat & sets some 
#	variables for $nick
###############################################################################
sub initiate_dcc_chat
{
	my ($server, $nick) = @_;

	print_debug("Initiating DCC CHAT to $nick");

	my %nickinfo = ();
	$nickinfo{status} 	= -1;
	$nickinfo{time} 	= 0;
	$nickinfo{ignore}	= 0;
	$nickinfo{dir} 		= '/';

	$fs_users{$nick} = { %nickinfo };
	$server->command("/DCC CHAT $nick");
}

###############################################################################
#	show_notice($server, $dest): displays server notice to $dest
#	($dest = #channel or nick)
###############################################################################
sub show_notice
{
	my ($dest) = @_;

	my $server = Irssi::server_find_tag($server_tag);
	if (!$server || !$server->{connected}) {
		print_msg("Error: this should never happen!!!");
		return;
	} 

	my $msg = "\002(\002FServe Online\002)\002 ";
	if ($fs_prefs{ignore_chat}) {
		$msg .= "Trigger:(/ctcp $$server{nick} $fs_prefs{trigger}) ";
	} else {
		$msg .= "Trigger:($fs_prefs{trigger}) ";
	}
	$msg .= "Accessed:($fs_stats{login_count} times) ";
	if (($fs_stats{sends_ok}+$fs_stats{sends_fail})) {
		$msg .= 'Snagged:('.size_to_str($fs_stats{transfd}).' in '.
				($fs_stats{sends_ok}+$fs_stats{sends_fail}).' files) ';
	}
	if ($fs_stats{record_cps}) {
		$msg .= 'Record CPS:('.size_to_str($fs_stats{record_cps}).'/s by '.
				$fs_stats{rcps_nick}.') ';
	}
	if ($fs_prefs{min_cps}) {
		$msg .= 'Min CPS:('.size_to_str($fs_prefs{min_cps}).'/s) ';
	}
	
	$msg .= 'Serving:('.size_to_str($fs_cache{bytecount}).' in '.
			"$fs_cache{filecount} files) ";
	if (keys %fs_users) {
	    $msg .= 'Online:('.(keys %fs_users)."/$fs_prefs{max_users}) ";
	}
	$msg .= 'Sends:('.@fs_sends."/$fs_prefs{max_sends}) ";
	$msg .= 'Queue:('.@fs_queue."/$fs_prefs{max_queue}) ";

	if (length($fs_prefs{note})) {
		$msg .= "Note:($fs_prefs{note}) ";
	}

	$msg .= $fs_prefs{logo};
	$msg =~ s/\(/\($fs_prefs{clr_hi}/g;
	$msg =~ s/\)/$fs_prefs{clr_txt}\)/g;

	if ($dest =~ /^#/) {
		$server->command("/MSG $dest $fs_prefs{clr_txt}$msg");
	} else {
		$server->command("/NOTICE $dest $fs_prefs{clr_txt}$msg");
	}
}

###############################################################################
#	change_dir($nick, $dir): changes directory for $nick
###############################################################################
sub change_dir
{
	my ($nick, $dir) = @_;

	my @dir_fields = ();
	unless (substr($dir, 0, 1) eq '/') {
		@dir_fields = split('/', $fs_users{$nick}{dir});
	}

	foreach (split('/', $dir)) {
		next if ($_ eq '.');
		if ($_ eq '..') {
			pop(@dir_fields);
		} else {
			push(@dir_fields, $_);
		}
	}

	my $new_dir = '/'.join('/', @dir_fields);
	$new_dir =~ s/\/+/\//g;		# remove excessive '/'

	if (defined $fs_cache{$new_dir}) {
		$fs_users{$nick}{dir} = $new_dir;
		send_user_msg($nick, "[$fs_prefs{clr_hi}$new_dir$fs_prefs{clr_txt}]");
	} else {
		send_user_msg($nick, "[$fs_prefs{clr_hi}$new_dir$fs_prefs{clr_txt}]".
					  " doesn't exist!");
	}
}

###############################################################################
#	list_dir($nick): list contents of current directory for $nick
###############################################################################
sub list_dir
{
	my ($nick) = @_;
	my $dir = $fs_users{$nick}{dir};
	my @filelist = ();

	send_user_msg($nick, "Listing [$fs_prefs{clr_hi}$fs_users{$nick}{dir}".
						 "$fs_prefs{clr_txt}]");

	# print the directories sorted
	send_user_msg($nick, $fs_prefs{clr_dir}.$_.$fs_prefs{clr_txt}.'/') 
	foreach (sort(@{ $fs_cache{$dir}{dirs} }));

	# prepare filelist
	foreach (0 .. $#{ $fs_cache{$dir}{files} }) {
		push(@filelist, @{ $fs_cache{$dir}{files}}[$_].
		     $fs_prefs{clr_txt}." (". $fs_prefs{clr_hi}.
		     size_to_str(@{ $fs_cache{$dir}{sizes} }[$_]).
		     $fs_prefs{clr_txt}.")");
	}

	# print the files sorted
	send_user_msg($nick, $fs_prefs{clr_file}.$_) foreach(sort(@filelist));
	send_user_msg($nick, "End [$fs_prefs{clr_hi}$fs_users{$nick}{dir}".
				  "$fs_prefs{clr_txt}]");
}

###############################################################################
#	srv_queue_file($nick, $file): queues any file for $nick, server use only
#				      (no max_queue and/or duplicate check)
###############################################################################
sub srv_queue_file
{
	my ($nick, $path) = @_;
	$path =~ s/~/$ENV{"HOME"}/;

	unless (-e $path || -f $path) {
		print_msg("Invalid file: '$path'");
		return;
	}

	my $size = (stat($path))[7];
	my @fields = split('/', $path);
	my $file = $fields[$#fields];
	$path =~ s/$file//;

	push(@fs_queue, { nick => $nick, file => $file, size => $size,
		 dir => $path });

	print_msg($fs_prefs{clr_hi}.'#'.@fs_queue.$fs_prefs{clr_txt}.
			  ": Queuing '$fs_prefs{clr_hi}$file$fs_prefs{clr_txt}".
			  "' for $fs_prefs{clr_hi}$nick$fs_prefs{clr_txt}!");
}

###############################################################################
#	srv_move_slot($slot, $dest): moves queue slots around
###############################################################################
sub srv_move_slot
{
	my ($slot, $dest) = @_;

	$slot--;
	$dest--;

	unless (defined $fs_queue[$slot] || defined $fs_queue[$dest]) {
		print_msg("Error: Invalid slot numbers!");
		return;
	}

	my %rec = %{ $fs_queue[$slot] };
	splice(@fs_queue, $slot, 1);
	splice(@fs_queue, $dest, 0, { %rec });

	print_msg("Moved slot $fs_prefs{clr_hi}#".($slot+1).$fs_prefs{clr_txt}.
			  " to $fs_prefs{clr_hi}#".($dest+1));
}


###############################################################################
#	queue_file($nick, $file): queues $file for $nick
###############################################################################
sub queue_file
{
	my ($nick, $ufile) = @_;
	my ($file, $size);

	# try to find the filename in cache
	my @files = @{ $fs_cache{$fs_users{$nick}{dir}}{files} };
	my @sizes = @{ $fs_cache{$fs_users{$nick}{dir}}{sizes} };

	foreach (0 .. $#files) {
		if (uc($files[$_]) eq uc($ufile)) {
			$file = $files[$_];
			$size = $sizes[$_];
			last;
		}
	}

	unless (defined $file) {
		send_user_msg($nick, "Invalid filename: '$fs_prefs{clr_hi}$ufile".
					  "$fs_prefs{clr_txt}'!");
		return;
	}

	my $force_queue = 0;
	if ($fs_prefs{ops_priority}) {
		my $server = Irssi::server_find_tag($server_tag);
		if (!$server || !$server->{connected}) {
			print_msg("Error: this should never happen!!!");
			return;
		}
		foreach my $channelName (split(' ', $fs_prefs{channels})) {
			my $channel = $server->channel_find($channelName);
			next if !$channel;
			my $n = $channel->nick_find($nick);
			next if !$n;
			if ($n->{op}) {
				send_user_msg($nick, "You are an op, and are being force-added ".
					"to the queue and bumped to the top of the list.");
				$force_queue = 1;
			} elsif ($n->{voice} && $fs_prefs{ops_priority} > 0) {
				send_user_msg($nick, "You are voiced, and are being force-added ".
					"to the queue and bumped to the top of the list.");
				$force_queue = 1;
			}
			last if $force_queue;
		}
	}

	if (!$force_queue) {
		if (count_queued_files($nick) >= $fs_prefs{user_slots}) {
			send_user_msg($nick, "No sends are available and you have ".
						  "used all your queue slots ($fs_prefs{clr_hi}".
						  "$fs_prefs{user_slots}$fs_prefs{clr_txt})");
			return;
		} elsif (@fs_queue >= $fs_prefs{max_queue}) {
			send_user_msg($nick, "No send or queue slots are available!");
			return;
		} else {
			foreach (0 .. $#fs_queue) {
				if ($fs_queue[$_]{nick} eq $nick && $fs_queue[$_]{file} eq $file) {
					send_user_msg($nick, "You have already queued '".
								  "$fs_prefs{clr_hi}$file$fs_prefs{clr_txt}'!");
					return;
				}
			}

			push(@fs_queue, { nick => $nick, file => $file, size => $size,
				 dir => $fs_prefs{root_dir}.$fs_users{$nick}{dir} });
		}
	}

	if ($force_queue) {
		unshift(@fs_queue, { nick => $nick, file => $file, size => $size,
			 dir => $fs_prefs{root_dir}.$fs_users{$nick}{dir} });
	}

	send_user_msg($nick, "Queued '$fs_prefs{clr_hi}$file$fs_prefs{clr_txt}".
			  "' (".$fs_prefs{clr_hi}.size_to_str($size).
			  $fs_prefs{clr_txt}.") in slot ".$fs_prefs{clr_hi}.
			  '#'.@fs_queue.$fs_prefs{clr_txt});
}

###############################################################################
#	dequeue_file($nick, $slot): dequeues file in slot $slot for $nick
###############################################################################
sub dequeue_file
{
	my ($nick, $slot) = @_;

	$slot -= 1;
	if (defined $fs_queue[$slot]) {
		if ($fs_queue[$slot]{nick} eq $nick) {
			send_user_msg($nick, "Removing $fs_prefs{clr_hi}".
						  "'$fs_queue[$slot]{file}$fs_prefs{clr_hi}', you now".
						  " have ".$fs_prefs{clr_hi}.count_queued_files().
						  $fs_prefs{clr_txt}." file(s) queued!");
			splice(@fs_queue, $slot, 1);
		} else {
			send_user_msg($nick, "You can't dequeue other peoples files!!!");
		}
	} else {
		send_user_msg($nick, "Queue slot $fs_prefs{clr_hi}#".($slot+1).
					  $fs_prefs{clr_txt}." doesn't exist!");
	}
}

###############################################################################
#	clear_queue($nick, $is_server): clears all queued files for $nick
###############################################################################
sub clear_queue
{
	my ($nick, $is_server) = @_;
	my $count = 0;

	if (count_queued_files($nick) == 0) {
		if ($is_server) {
			print_msg("$fs_prefs{clr_hi}$nick$fs_prefs{clr_txt} doesn't ".
					  "have any files queued!");
		} else {
			send_user_msg($nick, "You don't have any queued files!");
		}
	} else {
		for (my $i = $#fs_queue; $i >= 0; $i--) {
			if ($fs_queue[$i]{nick} eq $nick) {
				splice(@fs_queue, $i, 1);
				$count++;
			}
		}

		$nick = '!fserve!' if ($is_server);
		send_user_msg($nick, "Successfully dequeued $fs_prefs{clr_hi}".
			      "$count$fs_prefs{clr_txt} file(s)!");
	}
}

###############################################################################
#	display_queue($nick): displays queue to $nick
###############################################################################
sub display_queue
{
	my ($nick) = @_;

	send_user_msg($nick, $fs_prefs{clr_hi}.@fs_queue."/$fs_prefs{max_queue}".
				  "$fs_prefs{clr_txt} queued file(s)!");

	foreach (0 .. $#fs_queue) {
		send_user_msg($nick, "  $fs_prefs{clr_hi}#".($_+1)."$fs_prefs{clr_txt}".
					  ": $fs_prefs{clr_hi}$fs_queue[$_]{nick}$fs_prefs{clr_txt}".
					  " queued $fs_prefs{clr_hi}$fs_queue[$_]{file}$fs_prefs{clr_txt}".
					  " (".$fs_prefs{clr_hi}.size_to_str($fs_queue[$_]{size}).
					  $fs_prefs{clr_txt}.")");
	}
}

###############################################################################
#	display_who($nick): shows users connected to $nick
###############################################################################
sub display_who
{
	my ($nick) = @_;

	send_user_msg($nick, $fs_prefs{clr_hi}.keys(%fs_users).$fs_prefs{clr_txt}.
				  ' user(s) online!');

	foreach (keys(%fs_users)) {
		if ($fs_users{$_}{status} == -1) {
			send_user_msg($nick, "  $fs_prefs{clr_hi}$_$fs_prefs{clr_txt}:".
						  " connecting...");
		} else {
			send_user_msg($nick, "  $fs_prefs{clr_hi}$_$fs_prefs{clr_txt}:".
						  " online $fs_prefs{clr_hi}$fs_users{$_}{time}s".
						  $fs_prefs{clr_txt}.", ".$fs_prefs{clr_hi}."idle: ".
						  "$fs_users{$_}{status}s");
		}
	}
}

###############################################################################
#	display_sends($nick): shows active sends to $nick
###############################################################################
sub display_sends
{
	my ($nick) = @_;

	send_user_msg($nick, "Sending $fs_prefs{clr_hi}".@fs_sends.'/'.
				  $fs_prefs{max_sends}.$fs_prefs{clr_txt}." file(s)!");

	foreach my $dcc (Irssi::Irc::dccs()) {
		if ($dcc->{type} eq 'SEND') {
			foreach (0 .. $#fs_sends) {
				if ($dcc->{nick} eq $fs_sends[$_]{nick} &&
					$dcc->{arg} eq $fs_sends[$_]{file}) {
					
					if ($dcc->{starttime} == 0 ||
						($dcc->{transfd}-$dcc->{skipped}) == 0) {
						send_user_msg($nick, "  $fs_prefs{clr_hi}#".($_+1).
							"$fs_prefs{clr_txt}: Waiting for ".
							$fs_prefs{clr_hi}.$dcc->{nick}.$fs_prefs{clr_txt}.
							" to accept $fs_prefs{clr_hi}$dcc->{arg}".
							$fs_prefs{clr_txt}." (".$fs_prefs{clr_hi}.
							size_to_str($fs_sends[$_]{size}).
							$fs_prefs{clr_txt}.")");
						last;
					}
					
					my $perc = sprintf("%.1f%%", ($dcc->{transfd}/$dcc->{size})*100);
					my $speed = ($dcc->{transfd}-$dcc->{skipped})/(time() - $dcc->{starttime} + 1);
					my $left  = ($dcc->{size} - $dcc->{transfd}) / $speed;

					send_user_msg($nick, "  $fs_prefs{clr_hi}#".($_+1)."$fs_prefs{clr_txt}:".
								  " $fs_prefs{clr_hi}$dcc->{nick}$fs_prefs{clr_txt} ".
								  "has ".$fs_prefs{clr_hi}.$perc.$fs_prefs{clr_txt}.
								  " of '$fs_prefs{clr_hi}$dcc->{arg}$fs_prefs{clr_txt}'".
								  " at ".$fs_prefs{clr_hi}.size_to_str($speed)."/s".
								  $fs_prefs{clr_txt}." (".$fs_prefs{clr_hi}.
								  time_to_str($left).$fs_prefs{clr_txt}." left)");
					last;
				}
			}
		}
	}
}

###############################################################################
#	display_stats($nick): displays server statistics to $nick
###############################################################################
sub display_stats
{
	my ($nick) = @_;

	send_user_msg($nick, "-=[ Server Statistics ]=-");
	send_user_msg($nick, "  Online for ".$fs_prefs{clr_hi}.time_to_str($online_time));
	send_user_msg($nick, "  Access Count: ".$fs_prefs{clr_hi}.$fs_stats{login_count});
	send_user_msg($nick, " ");
	send_user_msg($nick, "  Successful Sends: ".$fs_prefs{clr_hi}.$fs_stats{sends_ok});
	send_user_msg($nick, "  Bytes Transferred: ".$fs_prefs{clr_hi}.size_to_str($fs_stats{transfd}));
	send_user_msg($nick, "  Failed Sends: ".$fs_prefs{clr_hi}.$fs_stats{sends_fail});
	send_user_msg($nick, "  Record CPS: ".$fs_prefs{clr_hi}.size_to_str($fs_stats{record_cps})."/s");
}

###############################################################################
## Shows a small file to the user
###############################################################################
sub display_file ($$) {
	my ($nick, $ufile) = @_;
	my ($file, $size, $dir, $filepath);

	# try to find the filename in cache
	my @files = @{ $fs_cache{$fs_users{$nick}{dir}}{files} };
	my @sizes = @{ $fs_cache{$fs_users{$nick}{dir}}{sizes} };

	foreach (0 .. $#files) {
		if (uc($files[$_]) eq uc($ufile)) {
			$file = $files[$_];
			$size = $sizes[$_];
			last;
		}
	}

	$dir = $fs_prefs{root_dir} . $fs_users{$nick}{dir};
	$filepath = "$dir" . "/" . "$ufile";

	unless (defined $file) {
		send_user_msg($nick, "Invalid filename: " .
			"'$fs_prefs{clr_hi}$ufile$fs_prefs{clr_txt}'!");
		return;
	}

	if ($size > 30000) {
		send_user_msg($nick, "File too large: " .
			"'$fs_prefs{clr_hi}$ufile$fs_prefs{clr_txt}'!");
		return;
	}

	unless (open (RFILE, $filepath)) {
		send_user_msg($nick, "Couldn't open file: " .
			"'$fs_prefs{clr_hi}$ufile$fs_prefs{clr_txt}'!");
		send_user_msg($nick, "Using file: $filepath");
		return;
	}

	while (my $line = <RFILE>) {
		send_user_msg($nick, $line);
	}

	unless (close (RFILE)) {
		send_user_msg($nick, "Couldn't close file: " .
			"'$fs_prefs{clr_hi}$ufile$fs_prefs{clr_txt}'!");
		return;
	}

	return 1;
}

###############################################################################
#	send_next_file($server): send the next file in queue
###############################################################################
sub send_next_file
{
	my ($server) = @_;
	my %entry = ();

	# step through the queue
	for (my $i = 0; $i < @fs_queue; $i++) {
		my $in_channel  = user_in_channel($fs_queue[$i]{nick});
		my $send_active = send_active_for($fs_queue[$i]{nick});
		my $file = $fs_queue[$i]{dir}.'/'.$fs_queue[$i]{file};
		$file =~ s/\/+/\//g;

		# send file if user in channel and has no sends active
		if (!$send_active && $in_channel && -e $file && -f $file) {
			$server->command("/NOTICE $fs_queue[$i]{nick} $fs_prefs{clr_txt}".
				"Sending you your queued file (".$fs_prefs{clr_hi}.
				size_to_str($fs_queue[$i]{size}).$fs_prefs{clr_txt}.")");
			$server->command("/DCC SEND $fs_queue[$i]{nick} $file");
			push(@fs_sends, { %{$fs_queue[$i]} });
			splice(@fs_queue, $i, 1);
			return 0;
		}
			
		# remove entry if user wasn't in channel of file didn't exist
		if (!$send_active) {
			print_msg("User $fs_prefs{clr_hi}$fs_queue[$i]{nick} ".
				"$fs_prefs{clr_txt} is not in channel,".
				" removing $fs_queue[$i]{file}".
				"$fs_prefs{clr_txt} from queue...");
			splice(@fs_queue, $i, 1);
			$i--;	# next slot will have same index
			next;
		}
	}

	return 1;
}

###############################################################################
#	update_files():	update the cache from $fs_prefs{root_dir}
###############################################################################
sub update_files
{
	my $filecount = 0;
	my $bytecount = 0;

	print_msg("Caching files, please wait!");
	# update the cache
	%fs_cache = ();
	cache_dir($fs_prefs{root_dir});

	foreach my $dir (keys %fs_cache) {
		$filecount += @{$fs_cache{$dir}{files}};
		$bytecount += $_ foreach (@{$fs_cache{$dir}{sizes}});
	}

	$fs_cache{filecount} = $filecount;
	$fs_cache{bytecount} = $bytecount;
	
	print_msg("Cached $filecount file(s) (".size_to_str($bytecount).") in ".
			  (keys(%fs_cache)-2)." dir(s)!");
}

###############################################################################
#	cache_dir($dir): recursive filecaching subroutine
###############################################################################
sub cache_dir
{
	my ($dir) = @_;
	my @dirs  = ();
	my @files = ();
	my @sizes = ();

	opendir($dir, "$dir");
	while (my $entry = readdir($dir)) {
		if (!($entry eq '.') && !($entry eq '..')) {
			my $full_path = $dir.'/'.$entry;
			if (-d $full_path) {
				push(@dirs, $entry);
				cache_dir($full_path);
			} elsif (-f $full_path) {
				push(@sizes, (stat($full_path))[7]);
				push(@files, $entry);
			}
		}
	}

	closedir($dir);

	$dir =~ s/$fs_prefs{root_dir}//;
	$dir = '/' if (length($dir) == 0);

	$fs_cache{$dir} = { dirs => [ @dirs ], files => [ @files ],
						sizes => [ @sizes ] };
}

###############################################################################
#	count_queued_files($nick): returns number of queued files for $nick
###############################################################################
sub count_queued_files
{
	my ($nick) = @_;
	my $count = 0;
	
	foreach (0 .. $#fs_queue) {
		$count++ if ($fs_queue[$_]{nick} eq $nick);
	}

	return $count;
}

###############################################################################
#	send_active_for($nick):	true if currently sending file to $nick
###############################################################################
sub send_active_for
{
	my ($nick) = @_;

	foreach (0 .. $#fs_sends) {
		return 1 if ($fs_sends[$_]{nick} eq $nick);
	}

	return 0;
}

###############################################################################
#	user_in_channel($nick): true if user is on any $fs_prefs{channels}
###############################################################################
sub user_in_channel
{
	my ($nick) = @_;

	my $server = Irssi::server_find_tag($server_tag);
	if (!$server || !$server->{connected}) {
		print_msg("Error: this should never happen!!!");
		return;
	}

	foreach (split(' ', $fs_prefs{channels})) {
		my $channel = $server->channel_find($_);
		if ($channel && $channel->{joined} && $channel->nick_find($nick)) {
			return 1;
		}
	}

	return 0;
}

###############################################################################
#	send_user_msg($nick, $msg):	sends a msg to $nick using dcc if available
###############################################################################
sub send_user_msg
{
	my ($nick, $msg) = @_;

	if ($nick eq "!fserve!") {
		print_msg($msg);
	} else {
		my $server = Irssi::server_find_tag($server_tag);
		if (!$server || !$server->{connected}) {
			print_msg("Error: this should never happen!!!");
			return;
		}

		my $cmd = ((defined $fs_users{$nick})?"/MSG =$nick":"/MSG $nick");
		$server->command("$cmd $fs_prefs{clr_txt}$msg");
	}
}

###############################################################################
#	size_to_str($size): returns a formatted size string
###############################################################################
sub size_to_str
{
	my ($size) = @_;

	if ($size < 1024) {
		$size = "$size B";
	} elsif ($size < 1048576) {
		$size = sprintf("%.1f kB", $size/1024);
	} elsif ($size < 1073741824) {
		$size = sprintf("%.1f MB", $size/1048576);
	} elsif ($size < 1099511627776) {
		$size = sprintf("%.1f GB", $size/1073741824);
	} else {
		$size = sprintf("%.1f TB", $size/1099511627776);
	}

	return $size;
}

###############################################################################
#	time_to_str($time): returns a formatted time string
###############################################################################
sub time_to_str
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime(shift(@_));

	return sprintf("%dd %dh %dm %ds", $yday, $hour, $min, $sec) if ($yday);
	return sprintf("%dh %dm %ds", $hour, $min, $sec) if ($hour);
	return sprintf("%dm %ds", $min, $sec) if ($min);
	return sprintf("%ds", $sec);
}

###############################################################################
#	save_config(): saves preferences & statistics to file
###############################################################################
sub save_config
{
	my $file = $ENV{HOME}.'/.irssi/fserve.conf';
	
	if (!open(FILE, ">$file")) {
		print_msg("Unable to open $file for writing!");
		return 1;
	}

	# save preferences
	foreach (sort(keys %fs_prefs)) {
		print(FILE "$_=$fs_prefs{$_}\n");
	}

	# save statistics
	foreach (sort(keys %fs_stats)) {
		print(FILE "$_=$fs_stats{$_}\n");
	}

	close(FILE);
	return 0;
}

###############################################################################
#	load_config(): loads preferences & statistics from file
###############################################################################
sub load_config
{
	my $file = $ENV{HOME}.'/.irssi/fserve.conf';

	if (!open(FILE, "<$file")) {
		print_msg("Unable to open $file for reading!");
		return 1;
	}

	local $/ = "\n";

	while (<FILE>) {
		s/\n//g;
		next if /^\s*(#.*)?$/; # ignore comments
		my ($entry, $value) = split('=', $_, 2);
		if (defined $fs_prefs{$entry}) {
			$fs_prefs{$entry} = $value;
		} elsif (defined $fs_stats{$entry}) {
			$fs_stats{$entry} = $value;
		} else {
			print_msg("unknown entry: $_");
		}
	}

	close(FILE);
	return 0;
}

###############################################################################
#	save_queue(): saves the current sends & queue to file
###############################################################################
sub save_queue
{
	my $file = $ENV{HOME}.'/.irssi/fserve.queue';

	if (!open(FILE, ">$file")) {
		print_msg("Unable to open $file for writing!");
		return 1;
	}

	# save the sends (for resuming)
	foreach my $slot (0 .. $#fs_sends) {
		foreach (sort(keys(%{$fs_sends[$slot]}))) {
			print(FILE "$_=>$fs_sends[$slot]{$_}:");
		}
		print(FILE "\n");
	}
	
	# save the queue
	foreach my $slot (0 .. $#fs_queue) {
		foreach (sort(keys(%{$fs_queue[$slot]}))) {
			print(FILE "$_=>$fs_queue[$slot]{$_}:");
		}
		print(FILE "\n");
	}

	close(FILE);
	return 0;
}

###############################################################################
#	load_queue(): loads the queue from file
###############################################################################
sub load_queue
{
	my $file = $ENV{HOME}.'/.irssi/fserve.queue';

	if (!open(FILE, "<$file")) {
		print_msg("Unable to open $file for reading!");
		return 1;
	}

	while (<FILE>) {
		s/\n//g;
		my %rec = ();

		foreach my $line (split(':', $_)) {
			my ($entry, $value) = split('=>', $line);
			$rec{$entry} = $value;
		}

		push(@fs_queue, { %rec });
	}

	close(FILE);
	return 0;
}

###############################################################################
# print_log(): write line to log file
###############################################################################
sub print_log
{
	if (!$logfp && $fs_prefs{log_name} && open(LOGFP, ">>$fs_prefs{log_name}")) {
		$logfp = \*LOGFP;
		select((select($logfp), $|++)[0]);
	}
	return if !$logfp;
	my ($msg) = @_;
	$msg =~ s/^\s*|\s*$//gs;
	print $logfp localtime()." $msg\n";
}
