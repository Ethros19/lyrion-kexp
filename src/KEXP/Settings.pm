package Plugins::KEXP::Settings;

# Read-only "about" page under Settings > Plugins: version, what's loaded,
# and links (a real, clickable Donate link for skins whose menus can't open one).

use strict;
use base qw(Slim::Web::Settings);

use Plugins::KEXP::LiveOnKEXP;

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_KEXP');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/KEXP/settings/basic.html');
}

sub beforeRender {
	my ($class, $params) = @_;

	$params->{kexpVersion}  = Plugins::KEXP::Plugin->_pluginDataFor('version');
	$params->{kexpSessions} = Plugins::KEXP::LiveOnKEXP->count;
	$params->{kexpDonate}   = Plugins::KEXP::Plugin::DONATE_URL();
	$params->{kexpProject}  = 'https://github.com/Ethros19/lyrion-kexp';
}

1;
