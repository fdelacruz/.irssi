#!/usr/bin/perl -w
# various kick and ban commands
#  by c0ffee 
#    - http://www.penguin-breeder.org/irssi/
use vars qw($VERSION %IRSSI);

use Irssi 20020120;
$VERSION = "0.10";
%IRSSI = (
    authors	=> "c0ffee",
    contact	=> "c0ffee\@penguin-breeder.org",
    name	=> "Various kick and ban commands",
    description	=> "Enhances /k /kb and /kn with some nice options. Note that these commands are not suitable for takeover defense or something. This might be added somewhere in the future.",
    license	=> "Public Domain",
    url		=> "http://www.penguin-breeder.org/irssi/",
    changed	=> "Tue Mar  5 11:33:48 CET 2002"
);
my $kicks_version = "v$VERSION";

my $help = 
"KICK [<options>] [#<channel>] [nick[,nick...]] [<reason>]\n" .
"KICKBAN [<options>] [#<channel>] [nick[,nick...]] [<reason>]\n" .
"\n".
"KICKBAN is an alias to KICK -ban\n".
"\n" .
"default options can be supplied with /set fancy_ban_options options\n" .
"kick_first_on_kickban, ban_type is honored\n".
"nick & alternate_nick are used\n".
"\n" .
"if [<reason>] is omitted a randrom kick reason will be choosen\n" .
"\n" .
"options:\n" .
" -ban              - bans the nick with default bantype\n" .
" -reban            - if a matching ban already exists, remove before\n" .
"                     adding new ban\n" .
" -deop             - deop before banning\n" .
" -bantype typ      - set bantype. possible types are\n" .
"                       normal      *!*user@*.domain.org\n" .
"                       host        *!*\@host.domain.org\n" .
"                       domain      *!*@*.domain.org\n" .
"                       tld         *!*@*.org\n" .
"                       sld         *!*@*.domain.org\n" .
"                         (tld/sld is top/second-level domain, handy\n" .
"                          for dns spammers)\n" .
"                       custom:nick,user,host,domain\n" .
"                                   combines the given elements\n" .
" -ignore           - ignores /msg and /ctcp stuff from nick\n" .
" -banonly          - don't kick (nick and reason may be omitted)\n" .
" -topic            - use current topic as kick reason\n" .
" -nick             - change nick to alternate_nick and vice versa\n" .
" -last min         - removes ban/ignore have min minutes\n" .
" -match hostmask   - kick everybody matching this mask (nick needs to be\n" .
"                     omitted)\n" .
" -invite           - set channel +i before banning\n" .
" -exec cmd         - do /cmd #channel nick hostmask after kicking\n" .
"                     (nick may be * if match/clones is used)\n" .
" -stop             - stop the current -match or -clones kick\n" .
" -nodefault        - ignores fancy_ban_options\n" .
" -clones           - kick everybody with the same hostmask as nick\n" .
" -help             - shows this help\n" .
"\n".
"kickreasons are read from ~/.irssi/kickreasons (or some default if\n" .
"that file doesn't exist)";
# nice kickreasons can be extracted from the offending fortune cookies...
# since they are stored rot13 and you can only use oneliners a little more
# perl is needed:
#
# perl -0777 -l \
#      -e '$all = <>;' \
#      -e '$all =~ y/a-zA-Z/n-za-mN-ZA-M/;' \
#      -e '@cookies = split "\n%\n", $all;' \
#      -e 'foreach (@cookies) {' \
#      -e '  print $2.$4."\n"' \
#      -e '    if (/(^(.+)$)|(^(.+)\n\s+--\s.+$)/);' \
#      -e '}' fortune-file
#
# the BOFH excuses are nice to (although not so offending... )

use Irssi;
use Irssi::Irc;

my $kickreasons_file = "$ENV{HOME}/.irssi/reasons/kicks";
my @kickreasons;
my @unbanqueue;
my $stop_idiot=0;

sub unbanner {
	my $idx;
	my @ops = ();

	
	for ($idx=0; $idx<@unbanqueue;) {
		$unbanqueue[$idx]->{left} -= 10;
		if ($unbanqueue[$idx]->{left} < 0) {
			push(@ops,splice(@unbanqueue,$idx,1));
		} else {
			++$idx;
		}
	}

	foreach $unbans (@ops) {

		my $chn = $unbans->{server}->channel_find($unbans->{channel});
		if ($chn) {

			if ($chn->{chanop}) {
				$chn->command("unban $unbans->{channel} $unbans->{hostmask}");
			} else {
				Irssi::print("could not unban $unbans->{hostmask} in $unbans->{channel}");
			}

		} else {
			Irssi::print("could not find channel $unbans->{channel} to unban $unbans->{hostmask}");
		}

	}
}


sub readreasons {
	undef @kickreasons;

	if (-f "$kickreasons_file") {
		open F, "$kickreasons_file";
		while (<F>) {
			chomp;
			push(@kickreasons, $_);
		}
		close F;
		Irssi::print("read kickreasons from ".$kickreasons_file );
	} else {
		@kickreasons = ("random kick victim",
				"no",
				"are you stupid?",
				"well...",
				"i don't like you, go away!",
				"oh, fsck off",
				"waste other ppls time, elsewhere",
				"get out and STAY OUT",
				"don't come back");
	}
	Irssi::timeout_add(10000,'unbanner',0);
}

sub getmasks {
	my ($channel, $hostmask) = @_;
	my @result = ();

	my $smask = quotemeta $hostmask;

	$smask =~ s/\\\*/.*/g;
	$smask =~ s/\\\?/./g;

	foreach my $chnban ($channel->bans()) {
		my $bmask = quotemeta $chnban->{ban};
		$bmask =~ s/\\\*/.*/g;
		$bmask =~ s/\\\?/./g;
	
		push(@result,$chnban->{ban}) if ($hostmask =~ /$bmask/) || ($chnban->{ban} =~ /$smask/);

	}
	
	@result;
}

sub deopban {
	my ($server, $nick, $channel, $hostmask, $reban) = @_;
	my $addmode = "";
	my $addnick = "";

	if ($reban == 1) {
		my @addbans = getmasks($channel, $hostmask);
		
		if (@addbans > 0) {
			$addnick = join(" ", @addbans);
			$addmode = "-b" x (scalar @addbans);
		}

	}
	
	$server->command("mode $channel->{name} -o$addmode+b $nick $addnick $hostmask");
}

sub kick {
	my ($server, $nick, $channel, $reason) = @_;

	$reason = $kickreasons[rand @kickreasons] if ($reason =~ /^\s*$/);
	$server->send_raw("KICK $channel->{name} $nick :$reason");
}

sub kickdeopban {
	my ($server, $nick, $channel, $hostmask, $reason, $reban) = @_;

	if (Irssi::settings_get_bool('kick_first_on_kickban')) {
		kick($server, $nick, $channel, $reason);
		deopban($server, $nick, $channel, $hostmask, $reban);
	} else {
		deopban($server, $nick, $channel, $hostmask, $reban);
		kick($server, $nick, $channel, $reason);
	}
}

sub banonly {
	my ($server, $channel, $hostmask, $reban) = @_;
	my $addmode = "";
	my $addnick = "";
	if ($reban == 1) {
		my @addbans = getmasks($channel, $hostmask);
		
		if (@addbans > 0) {
			$addnick = join(" ", @addbans);
			$addmode = "-b" x (scalar @addbans);
		}

	}
	$server->command("mode $channel->{name} $addmode+b $addnick $hostmask");
}

sub ignore {
	my ($server, $nick) = @_;
	
	Irssi::command("ignore $nick CTCPS MSGS NOTICES INVITES");
}


sub cmd_doit {
	my ($data, $server, $channel) = @_;
	my $nick = "";
	my $reason = "";
	my $nonick = 0;
	my $hostmask = "";
	my @args;
	my $allnicks;
	my ($doban, $bantype, $doignore, $banonly, $topic, $donick, $timeout) =
	("","","","","","","");
	my ($match, $doinvite, $doexec, $doclones, $dodeop,$mask, $doreban) =
	("","","","","","","");

	if ($data =~ /-stop/i) {
		$stop_idiot= 1;
		return;
	}


	if ($data =~ /-help/i) {
		Irssi::print($help, MSGLEVEL_CLIENTCRAP);
		Irssi::print("\nrunning kicks $kicks_version by c0ffee", MSGLEVEL_CLIENTCRAP);
		return;

	}

	if ((not defined $channel->{name}) or ($channel->{name} eq "") or
	    ($channel->{name} !~ /^#.+/)) {
		Irssi::print("You're not in a channel");
		return;
	}


	($data =~ /-nodefault/i) or ($data = Irssi::settings_get_str('fancy_ban_options') . " $data"); 

	$data =~ s/^\s+//;
	@args = split(/\s+/, $data);
	
	while (1) {
		$data = lc(shift(@args));
		last if not $data =~ /^-(\S+)$/;
		$data = $1;
		
		if ($data =~ /^ban$/) {
			$doban = 1;
		} elsif ($data =~ /^deop$/) {
			$dodeop = 1;
		} elsif ($data =~ /^reban$/) {
			$doreban = 1;
		} elsif ($data =~ /^ignore$/) {
			$doignore = 1;
		} elsif ($data =~ /^invite$/) {
			$doinvite = 1;
		} elsif ($data =~ /^clones$/) {
			$doclones = 1;
		} elsif ($data =~ /^nodefault$/) {
			# ignore...
		} elsif ($data =~ /^banonly$/) {
			$banonly = 1;
		} elsif ($data =~ /^topic$/) {
			$topic = 1;
		} elsif ($data =~ /^nick$/) {
			$donick = 1;
		} elsif ($data =~ /^exec$/) {
			$cmd = lc(shift(@args));

			if ((not defined $cmd) or ($cmd eq "")) {
				Irssi::print("invalid command");
			}
			$doexec = $cmd;
		} elsif ($data =~ /^match$/) {
			$mask = lc(shift(@args));

			if ((not defined $mask) or ($mask eq "")) {
				Irssi::print("invalid hostmask");
			}
			$match = $mask;
		} elsif ($data =~ /^last$/) {
			$mins = shift(@args);
			if ((defined $mins) and ($mins ne "")) {
				if ($mins =~ /^\d+$/) {
					$timeout = $mins;
					if ($timeout == 0) {
						Irssi::print("invalid timeout");
						return;
					}
				} else {
					Irssi::print("invalid timeout");
					return;
				}
			}
		} elsif ($data =~ /^bantype$/) {
			my $type = lc(shift(@args));

			if ((defined $type) and ($type ne "")) {
				$bantype = $type;
			} else {
				Irssi::print("invalid ban type");
				return;
			}
		} else {
			Irssi::print("unknown option $data");
			return;
		}
	}

	$nick = $data if ($mask eq "");

	if ($server->ischannel($nick) == 1) {
  		$channel = $server->channel_find($nick);
		if ($channel->{name} eq "") {
			Irssi::print("could not find channel $nick");
			return;
		}
		$nick = lc(shift(@args));
	}

	if (($nick =~ /,/) && (($mask ne "")  || ($doclones == 1))) {
		Irssi::print("cannot do -match or -clones for multiple nicks");
		return;
	}

	$allnicks = $nick;

	
	if (not $channel->{chanop}) {
		Irssi::print("you're not op in $channel->{name}");
	}
	$timeout = $timeout * 60;

	if ($topic == 1) {
		$reason = $channel->{topic}
	} else {
		$reason = join(" ", @args);
	}
	$reason = "$data $reason" if (($mask ne "") and ($data ne ""));
	
	if (($mask ne "") and ($doclones == 1)) {
		Irssi::print("can't do match kick and clones kick together");
		return;
	}

	if (($banonly == 1) and (($mask ne "") or ($doclones == 1))) {

		Irssi::print("can't banonly with match or clones");
		return;

	}

	if ($allnicks eq "") {
		$allnicks = "blub";
	 	$nonick = 1;
	}
	
	foreach $nick (split /,/, $allnicks) {

		if ($nonick == 1) {
			$nick = "";
			$nonick = 0;
		}
		if (((not defined $nick) or ($nick eq "")) and ($mask eq "")) {
			Irssi::print("missing nick");
			return;
		}

		
		if ((defined $nick) and ($nick ne "")) {

			if ((not defined $bantype) or ($bantype eq "")) {
				$bantype = lc(Irssi::settings_get_str('ban_type'));
				if ($bantype =~ /custom/) {
					$bantype =~ s/custom\s+/custom:/;
					$bantype =~ s/\s+/,/g;
				}
				$bantype = "normal" if ($bantype eq "");
			}

			if (not defined ($channel->nick_find($nick))) {
				Irssi::print("There is no $nick on $channel->{name}");
				return;
			}
			
			$hostmask = $channel->nick_find($nick)->{host};

			if ($bantype =~ /^normal$/) {
				if ($hostmask =~ /^(.*\@[0-9]+\.[0-9]+\.[0-9]+\.)[0-9]+$/) {
					$hostmask = $1 . "*";
				} else {
					$hostmask =~ s/\@.*?\./\@*./;
				}
				$hostmask =~ s/^[^a-zA-Z0-9]//;
				$hostmask = "*!*" . $hostmask;
			} elsif ($bantype =~ /^host$/) {
				$hostmask =~ s/.*\@/*!*\@/;
			} elsif ($bantype =~ /^tld$/) {
				$hostmask =~ s/\@.*\.(.+?)$/\@*.$1/;
				$hostmask =~ s/.*\@/*!*\@/;
			} elsif ($bantype =~ /^sld$/) {
				$hostmask =~ s/\@.*\.(.+?\..+?)$/\@*.$1/;
				$hostmask =~ s/.*\@/*!*\@/;
			} elsif ($bantype =~ /^domain$/) {
				if ($hostmask =~ /^(.*\@[0-9]+\.[0-9]+\.[0-9]+\.)[0-9]+$/) {
					$hostmask = $1 . "*";
				} else {
					$hostmask =~ s/\@.*?\./\@*./;
				}
				$hostmask =~ s/.*\@/*!*\@/;
			} elsif ($bantype =~ /^custom:(.+)$/) {
				my @types = split(",", $1);
				my ($bnick, $bhost, $bdomain, $buser);

				while (1) {
					$data = lc(shift(@types));
					last if ((not defined $data) or ($data eq ""));
					if ($data =~ /^nick$/) {
						$bnick = 1;
					} elsif ($data =~ /^host$/) {
						$bhost = 1;
					} elsif ($data =~ /^domain$/) {
						$bdomain = 1;
					} elsif ($data =~ /^user$/) {
						$buser = 1;
					} else {
						Irssi::print("unknown bantype");
						return;
					}
				}

				if (($bhost == 1) and ($bdomain == 1)) {
					Irssi::print("invalid bantype");
					return;
				}

				if (($bhost != 1) and ($bdomain != 1) and ($bnick != 1)
					and ($buser != 1)) {
					Irssi::print("no bantype given");
					return;
				}

				if ($bdomain == 1) {
					if ($hostmask =~ /^(.*\@[0-9]+\.[0-9]+\.[0-9]+\.)[0-9]+$/) {
						$hostmask = $1 . "*";
					} else {
						$hostmask =~ s/\@.*?\./\@*./;
					}
				} elsif ($bhost != 1) {
					$hostmask =~ s/\@.*/\@*/;
				}
				if ($buser == 1) {
				        $hostmask =~ s/^[^A-Za-z0-9]//;
					$hostmask = "*" . $hostmask;
				} else {
					$hostmask =~ s/.*\@/*\@/g;
				}
				if ($bnick == 1) {
					$hostmask = $nick . "!" . $hostmask;
				} else {
					$hostmask = "*!" . $hostmask;
				}

			} else {
				Irssi::print("unknown ban type");
				return;
			}
		}
		
		$hostmask = $mask if ($mask ne "");
		$mask = $hostmask if ($doclones == 1);

		

		if ($doinvite == 1) {
			$server->command("mode $channel->{name} +i");
		}

		if ($banonly == 1) {
			banonly($server,$channel,$hostmask,$doreban);
		} elsif ($mask ne "") {
			my @nicks = $channel->nicks();
			banonly($server,$channel,$hostmask,$doreban) if (($doban == 1) and (not (Irssi::settings_get_bool('kick_first_on_kickban'))));
			$timeout = 60 * $timeout if ($timeout > 0);
			foreach $nick (@nicks) {
				my ($user,$host) = split("@",$nick->{host});
				next if $nick->{nick} eq $server->{nick};
				next if (Irssi::mask_match($mask,$nick->{nick},$user,$host) == 0);
				if ($stop_idiot == 1) {
					Irssi::print("Eeeeks... aborting");
					$stop_idiot=0;
					return;
				}
				kick($server,$nick->{nick},$channel,$reason);
				if ($doignore == 1) {
					if ($timeout > 0) {
						ignore($server, "-time $timeout $nick");
					} else {
						ignore($server,$nick);
					}
				}
			}
			banonly($server,$channel,$hostmask,$doreban) if (($doban == 1) and (Irssi::settings_get_bool('kick_first_on_kickban')));
		} elsif ($doban == 1) {
			if ($dodeop == 1) {
				kickdeopban($server,$nick,$channel,$hostmask,$reason,$doreban);
			} else {
				if (Irssi::settings_get_bool('kick_first_on_kickban')) {
					
					kick($server,$nick,$channel,$reason);
					banonly($server,$channel,$hostmask,$doreban);
				} else {
					banonly($server,$channel,$hostmask,$doreban);
					kick($server,$nick,$channel,$reason);
				}
			}
		} else {
			kick($server,$nick,$channel,$reason);
		}

		if (($doignore == 1) and ($match eq "")) {
			if ($timeout > 0) {
				ignore($server, "-time $timeout $nick");
			} else {
				ignore($server,$nick);
			}
		}


		if ($timeout > 0) {

			push(@unbanqueue,{ server => $server, channel => $channel->{name}, hostmask => $hostmask, left => $timeout, type => "ban"});


		}

		$nick = "*" if ($match ne "");

		if ($doexec ne "") {
			$server->command("$doexec $channel->{name} $nick $hostmask");
		}

		# done. one lamer less
	}
	if ($donick == 1) {
		my $curnick = $server->{nick};
		my $nick1 = Irssi::settings_get_str('nick');
		my $nick2 = Irssi::settings_get_str('alternate_nick');

		if ($nick1 =~ /$curnick/i) {
			$server->command("nick $nick2");
		} elsif ($nick2 =~ /$curnick/i) {
			$server->command("nick $nick1");
		} else {
			Irssi::print("can't change current nick...");
		}
	}
}

sub cmd_kick {

	my ($data, $server, $channel) = @_;
	cmd_doit($data, $server, $channel);
	Irssi::signal_stop();

}

sub cmd_kickban {
	
	my ($data, $server, $channel) = @_;
	cmd_doit("-ban $data", $server, $channel);
	Irssi::signal_stop();

}


	
Irssi::settings_add_str("misc", "fancy_ban_options", "");
Irssi::command_bind('kick', 'cmd_kick');
Irssi::command_bind('kickban', 'cmd_kickban');
readreasons();
