package Plugins::KEXP::Settings;

# Read-only "about" page under Settings > Plugins: version, what's loaded,
# and links (a real, clickable Donate link for skins whose menus can't open one).

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

use Plugins::KEXP::LiveOnKEXP;

my $prefs = preferences('plugin.kexp');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_KEXP');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/KEXP/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(menuLocation iconStyle));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	# menus (and their icon) are registered at startup: say so on a change
	if ($params->{saveSettings} && grep { defined $params->{"pref_$_"} && $params->{"pref_$_"} ne $prefs->get($_) } qw(menuLocation iconStyle)) {
		$params->{warning} = Slim::Utils::Strings::string('PLUGIN_KEXP_RESTART_NEEDED');
	}

	return $class->SUPER::handler($client, $params, $callback, @args);
}

sub beforeRender {
	my ($class, $params) = @_;

	$params->{kexpVersion}  = Plugins::KEXP::Plugin->_pluginDataFor('version');
	$params->{kexpSessions} = Plugins::KEXP::LiveOnKEXP->count;
	$params->{kexpDonate}   = Plugins::KEXP::Plugin::DONATE_URL();
	$params->{kexpProject}  = 'https://github.com/Ethros19/lyrion-kexp';
}

1;
