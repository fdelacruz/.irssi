# System load average statusbar item
# for irssi 0.7.99, copyleft 2001 Johan Kiviniemi
#  /SET loadavg_min - The minimum load to show
#  /SET loadavg_refresh - How often the loadavg is refreshed
use Irssi::TextUI;
use strict;
use 5.6.0;

my ($refresh, $last_refresh, $refresh_tag) = (10);
my ($min_load, @loadavg) = (1, 0, 0, 0);

sub get_loadavg {
    my $filename = '/proc/loadavg';

    my @localavg;
    if (open my $fh, "<$filename") {
        my $line = <$fh> || "";
        chomp $line;
        @localavg = split / /, $line;
        close $fh;
    } else {
        Irssi::print("Failed to open <$filename: $!", MSGLEVEL_CLIENTERROR);
    }

    for (@localavg[ 0 .. 2 ]) {
        return unless defined;
        return unless /^\d+\.\d+$/;
    }
    @loadavg = @localavg[ 0 .. 2 ];
}

sub loadavg {
    my ($item, $get_size_only) = @_;

    get_loadavg();

    $min_load = Irssi::settings_get_int('loadavg_min');
    $min_load = 0 if $min_load < 0;
    if ($loadavg[0] < $min_load and $loadavg[1] < 0.75 * $min_load
      and $loadavg[2] < 0.50 * $min_load)
    {
        # load < min_load, don't print [Load: ] at all.
        if ($get_size_only) {
            $item->{min_size} = $item->{max_size} = 0;
        }
    } else {
        $item->default_handler($get_size_only, undef,
          sprintf("%.2f %.2f %.2f", @loadavg), 1);
    }
}

sub refresh_loadavg {
    Irssi::statusbar_items_redraw('loadavg');
}

sub read_settings {
    $refresh = Irssi::settings_get_int('loadavg_refresh');
    $refresh = 1 if $refresh < 1;
    return if $refresh == $last_refresh;
    $last_refresh = $refresh;

    Irssi::timeout_remove($refresh_tag) if $refresh_tag;
    $refresh_tag =
      Irssi::timeout_add($refresh * 1000, 'refresh_loadavg', undef);
}

Irssi::settings_add_int('misc', 'loadavg_min',     $min_load);
Irssi::settings_add_int('misc', 'loadavg_refresh', $refresh);

Irssi::statusbar_item_register('loadavg', '{sb Load: $0-}', 'loadavg');
Irssi::statusbars_recreate_items();

read_settings();
Irssi::signal_add('setup changed', 'read_settings');
