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

$ND::TEMPLATE->param(TITLE => 'Main Page');

our $BODY;
our $DBH;

if (param('cmd') eq 'fleet'){
	$DBH->begin_work;
	my $fleet = $DBH->prepare("SELECT id FROM fleets WHERE uid = ? AND fleet = 0");
	my ($id) = $DBH->selectrow_array($fleet,undef,$ND::UID);
	unless ($id){
		my $insert = $DBH->prepare(q{INSERT INTO fleets (uid,target,mission,landing_tick,fleet,eta) VALUES (?,$?,'Base',0,0,0)});
		$insert->execute($ND::UID,$ND::PLANET);
		($id) = $DBH->selectrow_array($fleet,undef,$ND::UID);
	}
	my $delete = $DBH->prepare("DELETE FROM fleet_ships WHERE fleet = ?");
	$delete->execute($id);
	my $insert = $DBH->prepare('INSERT INTO fleet_ships (fleet,ship,amount) VALUES (?,?,?)');
	$fleet = param('fleet');
	while ($fleet =~ m/((?:[A-Z][a-z]+ )*[A-Z][a-z]+)\s+((?:\d+|,)+)/g){
		my $amount = $2;
		$amount =~ s/,//;
		$insert->execute($id,$1,$amount);
	}
	$fleet = $DBH->prepare('UPDATE fleets SET landing_tick = tick() WHERE id = ?');
	$fleet->execute($id);
	$DBH->commit;
}
if (param('sms')){
	my $query = $DBH->prepare('UPDATE users SET sms = ? WHERE uid = ?');
	$query->execute(escapeHTML(param('sms')),$ND::UID);
}
if (isMember() && !$ND::PLANET && (param('planet') =~ m/(\d+)(?: |:)(\d+)(?: |:)(\d+)/)){
	my $query = $DBH->prepare(q{
UPDATE users SET planet = 
	(SELECT id from current_planet_stats where x = ? AND y = ? AND z = ?)
WHERE uid = ? });
	$query->execute($1,$2,$3,$ND::UID);
}
if(param('oldpass') && param('pass')){
	my $query = $DBH->prepare('UPDATE users SET password = MD5(?) WHERE password = MD5(?) AND uid = ?');
	$query->execute(param('pass'),param('oldpass'),$ND::UID);
}

my ($motd) = $DBH->selectrow_array("SELECT value FROM misc WHERE id='MOTD'");

$BODY->param(MOTD => parseMarkup($motd));
$BODY->param(Username => 'harv');
$BODY->param(isMember => isMember());
$BODY->param(isHC => isHC());
my @groups = map {name => $_}, sort keys %ND::GROUPS;
$BODY->param(Groups => \@groups);


my $query = $DBH->prepare(q{SELECT planet,defense_points,attack_points,scan_points,humor_points, (attack_points+defense_points+scan_points/20) as total_points, sms,rank FROM users WHERE uid = ?});

my ($planet,$defense_points,$attack_points,$scan_points,$humor_points,$total_points,$sms,$rank) = $DBH->selectrow_array($query,undef,$ND::UID);

$ND::PLANET = $planet unless $ND::PLANET;

$BODY->param(NDRank => $rank);
$BODY->param(DefensePoints => $defense_points);
$BODY->param(AttackPoints => $attack_points);
$BODY->param(ScanPoints => $scan_points);
$BODY->param(HumorPoints => $humor_points);
$BODY->param(TotalPoints => $total_points);

$BODY->param(hasPlanet => $planet);

if ($planet){
	my @row = $DBH->selectrow_array('SELECT ruler,planet,coords(x,y,z),size,sizerank
			,score,scorerank,value,valuerank,xp,xprank FROM current_planet_stats
			WHERE id = ?',undef,$planet);
	$BODY->param(PlanetName => "$row[0] OF $row[1] ($row[2])");
	$BODY->param(PlanetSize => "$row[3] ($row[4])");
	$BODY->param(PlanetScore => "$row[5] ($row[6])");
	$BODY->param(PlanetValue => "$row[7] ($row[8])");
	$BODY->param(PlanetXP => "$row[9] ($row[10])");
}


my $query = $DBH->prepare(q{SELECT f.fleet, coords(x,y,z), mission, sum(fs.amount) AS amount, landing_tick 
FROM fleets f 
	JOIN fleet_ships fs ON f.id = fs.fleet 
	JOIN current_planet_stats p ON f.target = p.id
WHERE f.uid = ? AND (f.fleet = 0 OR landing_tick > ?)
GROUP BY f.fleet, x,y,z, mission, landing_tick
ORDER BY f.fleet
});

$query->execute($ND::UID,$ND::TICK);
my @fleets;
while (my($fleet,$coords,$mission,$amount,$landing_tick) = $query->fetchrow){
	push @fleets,{Target => $coords, Mission => $mission, Amount => $amount, LandingTick => $landing_tick};
}
$BODY->param(Fleets => \@fleets);

$BODY->param(SMS => $sms);

1;

