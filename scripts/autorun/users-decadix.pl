# $Id: users.pl,v 1.1.1.1 2002/02/13 06:24:50 root Exp $

use Irssi 20020121.2020 ();
$VERSION = "0.12";
%IRSSI = (
	  authors     => 'Jean-Yves "decadix" Lefort',
	  contact     => 'jylefort\@brutele.be, decadix on IRCNet',
	  name        => 'users',
	  description => 'Adds a /users command similar to /names builtin, but displaying userhost too',
	  license     => 'BSD',
	  changed     => '$Date: 2002/02/13 06:24:50 $ ',
);

# usage:
#
#	as simple as typing /USERS in a channel window (the list will be
#	displayed in a new window)
#
# /format's:
#
#	users		list header
#			$0	channel name
#
#	users_nick	nick
#			$0	mode
#			$1	nick
#			$2	userhost
#
#	endofusers	end of list
#			$0	channel name
#			$1	total nick count
#			$2	op count
#			$3	halfop count
#			$4	voice count
#			$5	normal count
#
# changes:
#
#	2002-01-28	release 0.12
#			* added support for halfops
#
#	2002-01-28	release 0.11
#
#	2002-01-23	initial release

use strict;

sub nick_cmp {
  my $mode_cmp = ($_[1]->{op} << 2) + ($_[1]->{halfop} << 1) + $_[1]->{voice}
    cmp ($_[0]->{op} << 2) + ($_[0]->{halfop} << 1) + + $_[0]->{voice};
  return $mode_cmp ? $mode_cmp : lc $_[0]->{nick} cmp lc $_[1]->{nick};
}

sub users {
  my ($args, $server, $item) = @_;

  if ($item && $item->{type} eq "CHANNEL") {
    Irssi::command('/WINDOW NEW HIDDEN');
    my ($window, @nicks) = (Irssi::active_win(), $item->nicks());
    my ($ops, $halfops, $voices, $normals) = (0, 0, 0, 0);
    
    $window->set_name("U:$item->{name}");
    $window->printformat(MSGLEVEL_CRAP, "users", $item->{name});
    
    @nicks = sort { nick_cmp($a, $b) } @nicks;

    foreach my $nick (@nicks) {
      my $mode;
      if ($nick->{op}) {
	$mode = '@'; $ops++;
      } elsif ($nick->{halfop}) {
	$mode = '%'; $halfops++
      } elsif ($nick->{voice}) {
	$mode = '+'; $voices++;
      } else {
	$mode = ' '; $normals++;
      }
      $window->printformat(MSGLEVEL_CRAP, "users_nick",
			    $mode, $nick->{nick}, $nick->{host});
    }
    
    $window->printformat(MSGLEVEL_CRAP, "endofusers", $item->{name},
			 $ops + $halfops + $voices + $normals,
			 $ops, $halfops, $voices, $normals);
  }
}

Irssi::theme_register([
		       'users', '{names_users Users {names_channel $0}}',
		       'users_nick', '{hilight $0}$[9]1 {nickhost $[45]2}',
		       'endofusers', '{channel $0}: Total of {hilight $1} nicks {comment {hilight $2} ops, {hilight $3} halfops, {hilight $4} voices, {hilight $5} normal}',
		      ]);

Irssi::command_bind("users", "users");
