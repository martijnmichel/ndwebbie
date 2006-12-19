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

use strict;

$ND::TEMPLATE->param(TITLE => 'CovOp Targets');

our $BODY;
our $DBH;
our $LOG;

die "You don't have access" unless isMember();

my $show = q{AND ((planet_status IS NULL OR NOT planet_status IN ('Friendly','NAP')) AND  (relationship IS NULL OR NOT relationship IN ('Friendly','NAP')))};
$show = '' if param('show') eq 'all';
if (param('covop') =~ /^(\d+)$/){
	my $update = $DBH->prepare('UPDATE covop_targets SET covop_by = ?, last_covop = tick() WHERE planet = ? ');
	$update->execute($ND::UID,$1);
}

my $list = '';
my $where = '';
if (param('list') eq 'distwhores'){
	$list = '&amp;list=distwhores';
	$where = qq{WHERE dists > 0 $show
ORDER BY dists DESC,COALESCE(sec_centres::float/structures*100,0)ASC}
}else{
	$where = qq{WHERE MaxResHack > 130000 
		$show
ORDER BY COALESCE(sec_centres::float/structures*100,0) ASC,MaxResHack DESC,metal+crystal+eonium DESC};
}

my $query = $DBH->prepare(qq{SELECT id, coords, metal, crystal, eonium, sec_centres::float/structures*100 AS secs, dists, last_covop, username, MaxResHack
FROM (SELECT p.id,coords(x,y,z), metal,crystal,eonium,
	sec_centres,NULLIF(structures,0) AS structures,dists,last_covop,
	u.username,max_bank_hack(metal,crystal,eonium,p.value,(SELECT value FROM
	current_planet_stats WHERE id = ?)) AS MaxResHack, planet_status, relationship
FROM covop_targets c JOIN current_planet_stats p ON p.id = c.planet
	LEFT OUTER JOIN users u ON u.uid = c.covop_by) AS foo
	$where});
$query->execute($ND::PLANET);

my @targets;
my $i = 0;
while (my ($id,$coords,$metal,$crystal,$eonium,$seccents,$dists,$lastcovop,$user,$max) = $query->fetchrow){
	$i++;
	push @targets,{Username => $user, Target => $id, Coords => $coords
		, Metal => $metal, Crystal => $crystal, Eonium => $eonium, SecCents => $seccents
		, Dists => $dists, MaxResHack => $max, LastCovOp => $lastcovop, List => $list, ODD => $i % 2};
}
$BODY->param(Targets => \@targets);

1;
