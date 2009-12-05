# /GREP <regexp_search> <command to run>
# For irssi 0.7.99 by Timo Sirainen
# v1.01

# TODO: /GREP "foo bar" command, options: -i, -w, -v

use Irssi;
use strict;

my $grepping = 0;
my $match;

sub sig_text {
  my ($dest, $text, $stripped_text) = @_;
  Irssi::signal_stop() if ($grepping && $stripped_text !~ /$match/);
}

sub cmd_grep {
  my $cmd;
  ($match, $cmd) = split(/ /, $_[0], 2);

  $grepping = 1;
  Irssi::command($cmd);
  $grepping = 0;
}

Irssi::signal_add_first('print text', 'sig_text');
Irssi::command_bind('grep', 'cmd_grep');
