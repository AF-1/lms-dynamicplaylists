#
# Dynamic Playlists 4
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::DynamicPlaylists4::ProtocolHandler;

use strict;
use warnings;
use utf8;
use base qw(FileHandle);
use Slim::Utils::Log;
use URI;

my $log = logger('plugin.dynamicplaylists4');

sub overridePlayback {
	my ($class, $client, $url) = @_;

	my $uri = URI->new($url);
	return undef unless $uri->scheme eq 'dynamicplaylist';

	if ( Slim::Player::Source::streamingSongIndex($client) ) {
		# don't start immediately if we're part of a playlist and previous track isn't done playing
		return undef if $client->controller()->playingSongDuration()
	}

	my ($playlistID, $query) = $url =~ m{^dynamicplaylist://([^?]+)(?:\?(.*))?$};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistID = '.Data::Dump::dump($playlistID));
	return undef unless defined $playlistID;

	my $command = ["dynamicplaylist", "playlist", "play", "playlistid:".$playlistID];

	if ($query) {
		my $cnt = 1;
		while (my ($value) = $query =~ /p${cnt}=([^&]*)/) {
			push @{$command}, "dynamicplaylist_parameter_${cnt}:$value";
			$cnt++;
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('client command = '.Data::Dump::dump($command));
	$client->execute($command);
	return 1;
}

sub canDirectStream {
	return 0;
}

sub isAudioURL {
	return 1;
}

sub isRemote {
	return 0;
}

sub contentType {
	return 'dynamicplaylist';
}

sub getIcon {
	return Plugins::DynamicPlaylists4::Plugin->_pluginDataFor('icon');
}

sub getMetadataFor {
	my ($class, $client, $url) = @_;
	return unless $client && $url;
	return {
		cover => $class->getIcon(),
	};
}

1;
