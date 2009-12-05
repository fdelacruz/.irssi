#!/usr/bin/perl -w
# various kick and ban commands
#  by c0ffee 
#    - http://www.penguin-breeder.org/irssi/

#<scriptinfo>
use vars qw($VERSION %IRSSI);

use Irssi 20020120;
$VERSION = "0.1";
%IRSSI = (
    authors	=> "c0ffee",
    contact	=> "c0ffee\@penguin-breeder.org",
    name	=> "Various kick and ban commands",
    description	=> "Enhances /k /kb and /kn with some nice options.",
    license	=> "Public Domain",
    url		=> "http://www.penguin-breeder.org/irssi/",
    changed	=> "Tue Jan 22 00:08 CET 2002",
);
#</scriptinfo>

my %kickreasons  = (
	default => ["random kick victim",
		    "no",
		    "are you stupid?",
		    "i don't like you, go away!",
		    "oh, fsck off",
		    "waste other ppls time, elsewhere",
		    "get out and STAY OUT",
		    "don't come back",
		    "no thanks",
		    "on popular demand, you are now leaving the channel",
		    "\$N",
		    "*void*",
		    "/part is the command you're looking for",
		    "this is the irssi of borg. your mIRC will be assimilated. resitance is futile."
		   ],
	none	=> [""],
	topic	=> ["\$topic"],
);


# fine tune the script for different chatnets
#    cmdline		regular expr that matches a correct cmdline for /k
#    req_chan		0/1 whether the channel is always part of the cmdline
#    num_nicks		number of nicks ... (-1 = inf)
#    start_with_dash	0/1 whether the normal cmdline may start with a dash
#    match_chn		matches channels
#    match_n		match nicks
#    match_reason	matches reasons
#    default_reason	reason to give as "no reason"
my %cfg = (
	IRC	=> {
			cmdline_k       => '\s*[!#+&][^\x0\a\n\r ]+\s+[-\[\]\\\\\`{}\w_|]+(,[-\[\]\\\\\`{}\w_|]+)*\s+\S.*',
			req_chan        => 0,
			num_nicks       => 3, # actually, /k takes more, but
			                      # normal irc servers only take
					      # three in a row
			start_with_dash => 1,
			match_chn       => '([!#+&][^\x0\a\n\r ]+)',
			match_n         => '\s([-\[\]\\\\\`{}\w_|]+(:?,[-\[\]\\\\\`{}\w_|]+)*)',
			match_reason    => '^\s*[!#+&][^\x0\a\n\r ]+\s+[-\[\]\\\\\`{}\w_|]+(:?,[-\[\]\\\\\`{}\w_|]+)*\s+(\S.*)$',
			default_reason  => '$N'
		}
);

sub initialize {

    my $conf_file = Irssi::settings_get_str("kicks_configuration");
    my ($basedir) = $conf_file =~ /^(.*\/).*?/;

    if (-f $conf_file) {
	open CONF, $conf_file;
	
	while (<CONF>) {
	    $line++;

	    next if /^\s*#/;

	    chomp;
	    ($key, $reasons) = /^(\S+)\s+(.+)\s*$/ or next;

	    if ($reasons =~ /\`([^\s]+).*?\`/) {
		$kickreasons{$key} = "$reasons";
		Irssi::print("Added executable $1 as $key...");
		next;
	    }

	    $reasons =~ s/^"(.*)"$/$1/;
	    $reasons =~ s/~/$ENV{HOME}/;
	    $reasons =~ s/^([^\/])/$basedir$1/;
	    
	    if (-f $reasons) {

		$kickreasons{$key} = [];

		open REASON, $reasons;

		while (<REASON>) {
		    chomp;
		    push @{$kickreasons{$key}}, $_;
		}

		close REASON;
		Irssi::print("Loaded $reasons as $key...");
	    } else {
		Irssi::print("can't parse config line $line...");
	    }
	}
	close CONF;
    } else {
        Irssi::print("Could not find configuration file for kicks...");
	Irssi::print("... use /set kicks_configuration <file>");
    }
}

			
sub get_a_reason {
    my ($topic) = @_;


    return "" if not defined $kickreasons{$topic};

    $_ = eval $kickreasons{$topic}, chomp, s/[\n\t]+/ /mg, return $_
        if ref($kickreasons{$topic}) ne "ARRAY";

    return $kickreasons{$topic}[rand @{$kickreasons{$topic}}];
    

}

sub cmd_realkick {
    my ($data, $server, $channel, $cmd) = @_;
    my $reasons = "default";

    return if not $server
              or not defined $cfg{$server->{chat_type}}
    	      or $data =~ /^$cfg{$server->{chat_type}}{cmdline_k}$/;

    Irssi::signal_stop();

    # let's see whether some options where supplied
    $default = Irssi::settings_get_str("default_kick_options");
    $data = "$default $data" if not $default =~ /^\s*$/;
    @opts = split /\s+/, $data;

    while (($opt) = (shift @opts) =~ /^\s*-(\S+)/) {
      
        $data =~ s/^\s*--\s+//, last if $opt eq "-";
      
        $data =~ s/^\s*-$opt\s+//, 
            $reasons = lc $opt,
	    next if defined $kickreasons{lc $opt};

        last if $cfg{$server->{chat_type}}{start_with_dash};

        Irssi::print("Unknown option -$opt");
        $fail = true;

    }

    return if $fail;

    $data =~ s/(^\s*)|(\s*$)//g;

    # do we need to add an channel?
    $data =~ s/^/$channel->{name} /
        if not $cfg{$server->{chat_type}}{req_chan}
           and not $data =~ /^$cfg{$server->{chat_type}}{match_chn}\s/;

    # is a reason already supplied?
    $reason = get_a_reason($reasons), $add_reason = 1
        if not (($reason) = $data =~ /$cfg{$server->{chat_type}}{match_reason}/);

    $reason = $cfg->{$server->{chat_type}}{default_reason}, $add_reason = 1
        if $reason =~ /^\s*$/;
    
    @nicks = split /,/, ($data =~ /$cfg{$server->{chat_type}}{match_n}/)[0];

    undef @commands;

    if ((($num_nicks = $cfg{$server->{chat_type}}{num_nicks}) != -1)
       and (@nicks > $num_nicks)) {

        while (@nicks) {
            $tmp = $data;
	    $tmp =~ s/$cfg{$server->{chat_type}}{match_n}/" " . join ",",(splice @nicks,0,$num_nicks)/e;
	    $tmp .= " $reason" if $add_reason;
	    push @commands, $tmp;
        }

    } else {
     
        $data .= " $reason" if $add_reason;
        push @commands, $data;

    }
    
    foreach (@commands) {
      if ($_ =~ /^$cfg{$server->{chat_type}}{cmdline_k}$/) {
        $channel->command("EVAL $cmd $_") 
      } else {
        Irssi::print("BUG: generated invalid $cmd command: $_");
      }
    }
}

sub cmd_kick {
    my ($data, $server, $channel) = @_;

    cmd_realkick $data, $server, $channel, "KICK";

}

sub cmd_kickban {
    my ($data, $server, $channel) = @_;

    cmd_realkick $data, $server, $channel, "KICKBAN";

}

Irssi::settings_add_str("misc", "default_kick_options", "");
Irssi::settings_add_str("misc", "kicks_configuration",
				"$ENV{HOME}/.irssi/kicks.conf");

Irssi::command_bind("kick", "cmd_kick");
Irssi::command_bind("kickban", "cmd_kickban");

initialize();
