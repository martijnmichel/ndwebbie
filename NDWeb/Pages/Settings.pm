#**************************************************************************
#   Copyright (C) 2006 by Michael Andreen <harvATruinDOTnu>               *
#                                                                         *
#   This program is free software; you can redistribute it and/or modify  *
#   it under the terms of the GNU General Public License as published by  *
#   the Free Software Foundation; either version 2 of the License, or     *
#   (at your option) any later version.                                   *
#                                                                         *
#   This program is distributed in the hope that it will be useful,       *
#   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
#   GNU General Public License for more details.                          *
#                                                                         *
#   You should have received a copy of the GNU General Public License     *
#   along with this program; if not, write to the                         *
#   Free Software Foundation, Inc.,                                       *
#   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.         *
#**************************************************************************/

package NDWeb::Pages::Settings;
use strict;
use warnings FATAL => 'all';
use ND::Include;
use CGI qw/:standard/;
use NDWeb::Include;

use base qw/NDWeb::XMLPage/;

$NDWeb::Page::PAGES{settings} = __PACKAGE__;

sub render_body {
	my $self = shift;
	my ($BODY) = @_;
	$self->{TITLE} = 'Edit site preferences';
	my $DBH = $self->{DBH};

	if (defined param 'cmd'){
		if(param('cmd') eq 'stylesheet'){
			my $query = $DBH->prepare(q{UPDATE users SET css = NULLIF($2,'Default') WHERE uid = $1});
			$query->execute($ND::UID,escapeHTML(param 'stylesheet')) or $ND::ERROR .= p $DBH->errstr;
		}
	}
	if(param('oldpass') && param('pass')){
		my $query = $DBH->prepare('UPDATE users SET password = MD5(?) WHERE password = MD5(?) AND uid = ?');
		$query->execute(param('pass'),param('oldpass'),$ND::UID);
	}
	my ($css) = $DBH->selectrow_array(q{SELECT css FROM users WHERE uid = $1},undef,$ND::UID);
	my @stylesheets = ({Style => 'Default'});
	$css = '' unless defined $css;
	while (<stylesheets/*.css>){
		if(m{stylesheets/(\w+)\.css}){
			push @stylesheets,{Style => $1, Selected => $1 eq $css ? 1 : 0};
		}
	}
	$BODY->param(StyleSheets => \@stylesheets);
	return $BODY;
}

1;
