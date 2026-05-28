#
# Dynamic Playlists 4
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::DynamicPlaylists4::Settings::BaseSettings;

use strict;
use warnings;
use utf8;
use base qw(Slim::Web::Settings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.dynamicplaylists4');
my $log = logger('plugin.dynamicplaylists4');

my $plugin;
my %subPages = ();

sub new {
	my $class = shift;
	$plugin = shift;
	my $default = shift;

	if (!defined($default) || !$default) {
		Slim::Web::Pages->addPageFunction($class->page, $class);
	} else {
		$class->SUPER::new();
	}
	$subPages{$class->name()} = $class;
}

sub handler {
	my ($class, $client, $params) = @_;

	my %currentSubPages = ();
	for my $key (keys %subPages) {
		my $pages = $subPages{$key}->pages($client, $params);
		for my $page (@{$pages}) {
			$currentSubPages{$page->{'name'}} = $page->{'page'};
		}
	}
	$params->{'subpages'} = \%currentSubPages;
	$params->{'subpage'} = $class->currentPage($client, $params);
	return $class->SUPER::handler($client, $params);
}

1;
