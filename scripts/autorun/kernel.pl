# Fetches the version(s) of the latest kernel(s).
# For Irssi. Copyleft Johan Kiviniemi, Ion@IRCNet

use strict;
use Irssi;
use IO::Socket;

sub finger($$) {
    # Yes, Net::Finger is already done and i'm reinventing the wheel.
    my ($user, $host) = @_;
    my $buffer;
    if (
      my $socket = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => 'finger(79)',
        Proto    => 'tcp',
      ))
    {
        if (syswrite $socket, "$user\n") {
            unless (sysread $socket, $buffer, 1024) {
		# Should i use $! here?
                Irssi::print("Unable to read from the socket: $!",
                  Irssi::MSGLEVEL_CLIENTERROR);
            }
        } else {
	    # ..and here?
            Irssi::print("Unable to write to the socket: $!",
              Irssi::MSGLEVEL_CLIENTERROR);
        }
    } else {
        Irssi::print("Connection to $host failed: $!",
          Irssi::MSGLEVEL_CLIENTERROR);
    }
    return $buffer;
}

sub get_version {
    my @version;
    if (my $finger = finger("", "finger.kernel.org")) {
	# The magic of the regexps :)
        @version = $finger =~ /:\s*(\S+)\s*$/gm;
	# Modify this to do whatever you want.
        Irssi::print("@version");
    }
}

Irssi::command_bind('kernel_version', 'get_version');
