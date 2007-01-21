#!/usr/bin/perl -w -T
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

package ND;
use CGI qw/:standard/;
use DBI;
use DBD::Pg qw(:pg_types);
use Apache2::Request;
use ND::DB;
use ND::Web::Page;
use strict;
use warnings;

$SIG{__WARN__} = sub {$ND::ERROR .= p $_[0]};

chdir '/var/www/ndawn/code';

sub handler {
	local $ND::r = shift;
	local $ND::req = Apache2::Request->new($ND::r, POST_MAX => "1M");
	local $ND::DBH = ND::DB::DB();
	local $ND::UID;
	local $ND::ERROR;
	my $page = $ND::req->param('page');

	if ($ENV{'SCRIPT_NAME'} =~ /(\w+)(\.(pl|php|pm))?$/){
		$page = $1 unless $1 eq 'index' and $3 eq 'pl';
	}
	$page = ND::Web::Page->new(PAGE => $page, DBH => $ND::DBH, URI => $ENV{REQUEST_URI}, USER_AGENT => $ENV{HTTP_USER_AGENT}, HTTP_ACCEPT => $ENV{HTTP_ACCEPT});
	$page->render;

	$ND::DBH->rollback unless $ND::DBH->{AutoCommit};
	$ND::DBH->disconnect;

	return Apache2::Const::OK;
}

1;
