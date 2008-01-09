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

package NDWeb::Pages::GalaxyRankings;
use strict;
use warnings FATAL => 'all';
use CGI qw/:standard/;
use NDWeb::Include;

use base qw/NDWeb::XMLPage/;

$NDWeb::Page::PAGES{galaxyrankings} = __PACKAGE__;

sub parse {
	#TODO: Need to fix some links first
	#if ($uri =~ m{^/[^/]+/(\w+)}){
	#	param('order',$1);
	#}
}

sub render_body {
	my $self = shift;
	my ($BODY) = @_;
	$self->{TITLE} = 'Top Galaxies';
	my $DBH = $self->{DBH};

	return $self->noAccess unless $self->isMember;

	my $error = '';

	$BODY->param(isHC => $self->isHC);

	my $offset = 0;
	if (defined param('offset') && param('offset') =~ /^(\d+)$/){
		$offset = $1;
	}
	$BODY->param(Offset => $offset);
	$BODY->param(PrevOffset => $offset - 100);
	$BODY->param(NextOffset => $offset + 100);

	my $order = 'scorerank';
	if (defined param('order') && param('order') =~ /^(scorerank|sizerank|planets|xprank|avgscore)$/){
		$order = $1;
	}
	$BODY->param(Order => $order);
	$order .= ' DESC' unless $order =~ /rank$/;


	#my $extra_columns = '';
	#if ($self->isHC){
	#	$extra_columns = ",galaxy_status,hit_us, galaxy,relationship,nick";
	#}
	my $query = $DBH->prepare(qq{SELECT x,y,
		size, size_gain, size_gain_day,
		score,score_gain,score_gain_day,
		value,value_gain,value_gain_day,
		xp,xp_gain,xp_gain_day,
		sizerank,sizerank_gain,sizerank_gain_day,
		scorerank,scorerank_gain,scorerank_gain_day,
		valuerank,valuerank_gain,valuerank_gain_day,
		xprank,xprank_gain,xprank_gain_day,
		planets,planets_gain,planets_gain_day
	FROM galaxies g WHERE tick = ( SELECT max(tick) AS max FROM galaxies)
	ORDER BY $order LIMIT 100 OFFSET ?});
	$query->execute($offset) or $error .= p($DBH->errstr);
	my @galaxies;
	while (my $galaxy = $query->fetchrow_hashref){
		for my $type (qw/planets size score xp value/){
			#$galaxy->{$type} = prettyValue($galaxy->{$type});
			next unless defined $galaxy->{"${type}_gain_day"};
			$galaxy->{"${type}img"} = 'stay';
			$galaxy->{"${type}img"} = 'up' if $galaxy->{"${type}_gain_day"} > 0;
			$galaxy->{"${type}img"} = 'down' if $galaxy->{"${type}_gain_day"} < 0;
			unless( $type eq 'planets'){
				$galaxy->{"${type}rankimg"} = 'stay';
				$galaxy->{"${type}rankimg"} = 'up' if $galaxy->{"${type}rank_gain_day"} < 0;
				$galaxy->{"${type}rankimg"} = 'down' if $galaxy->{"${type}rank_gain_day"} > 0;
			}
			for my $type ($type,"${type}_gain","${type}_gain_day"){
				$galaxy->{$type} =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1,/g; #Add comma for ever 3 digits, i.e. 1000 => 1,000
			}
		}
		push @galaxies,$galaxy;
	}
	$BODY->param(Galaxies => \@galaxies);
	$BODY->param(Error => $error);
	return $BODY;
}

1;
