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

package NDWeb::Pages::DefRequest;
use strict;
use warnings FATAL => 'all';
use CGI qw/:standard/;
use NDWeb::Include;

use base qw/NDWeb::XMLPage/;

$NDWeb::Page::PAGES{defrequest} = __PACKAGE__;

sub render_body {
	my $self = shift;
	my ($BODY) = @_;
	$self->{TITLE} = 'Request Defense';
	my $DBH = $self->{DBH};

	return $self->noAccess unless $self->isMember;

	my $error;

	if (defined param('cmd') && param('cmd') eq 'submit'){
		my $insert = $DBH->prepare('INSERT INTO defense_requests (uid,message) VALUES (?,?)');
		if($insert->execute($ND::UID,param('message'))){
			$BODY->param(Reply => param('message'));
		}else{
			$error .= "<b>".$DBH->errstr."</b>";
		}
	}
	$BODY->param(Error => $error);
	return $BODY;
}
1;
