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

$ND::TEMPLATE->param(TITLE => 'Launch Confirmation');

our $BODY;
our $DBH;
our $LOG;



die "You don't have access" unless isMember();

if (param('cmd') eq 'submit'){
	my $missions = param('mission');
	my $findplanet = $DBH->prepare("SELECT planetid(?,?,?,?)");
	my $findattacktarget = $DBH->prepare(q{SELECT c.target,c.wave,c.launched FROM  raid_claims c
		JOIN raid_targets t ON c.target = t.id
		JOIN raids r ON t.raid = r.id
		WHERE c.uid = ? AND r.tick+c.wave-1 = ? AND t.planet = ?
		AND r.open AND not r.removed});
	my $finddefensetarget = $DBH->prepare(q{SELECT NULL});
	my $addattackpoint = $DBH->prepare('UPDATE users SET attack_points = attack_points + 1 WHERE uid = ?');
	my $launchedtarget = $DBH->prepare('UPDATE raid_claims SET launched = True WHERE uid = ? AND target = ? AND wave = ?');
	my $addfleet = $DBH->prepare(qq{INSERT INTO fleets (uid,target,mission,landing_tick,fleet,eta) VALUES (?,?,?,?,(SELECT max(fleet)+1 from fleets WHERE uid = ?),?)});
	my $addships = $DBH->prepare('INSERT INTO fleet_ships (fleet,ship,amount) VALUES (?,?,?)');

	my $fleet = $DBH->prepare("SELECT id FROM fleets WHERE uid = ? AND fleet = 0");
	my ($basefleet) = $DBH->selectrow_array($fleet,undef,$ND::UID);
	unless ($basefleet){
		my $insert = $DBH->prepare(q{INSERT INTO fleets (uid,target,mission,landing_tick,fleet,eta) VALUES (?,?,'Base',0,0,0)});
		$insert->execute($ND::UID,$ND::PLANET);
	}
	my @missions;
	$DBH->begin_work;
	while ($missions =~ m/\S+\s+(\d+):(\d+):(\d+)\s+(\d+):(\d+):(\d+)\s+\((?:(\d+)\+)?(\d+)\).*?(?:\d+hrs\s+)?\d+mins\s+(Attack|Defend|Return|Fake Attack|Fake Defend)(.*?)(?:Launching in tick (\d+), arrival in tick (\d+)|ETA: \d+, Return ETA: (\d+))/sg){
		my %mission;

		my $tick = $ND::TICK+$7+$8;
		my $eta = $8;
		my $mission = $9;
		my $x = $4;
		my $y = $5;
		my $z = $6;
		$mission{Tick} = $tick;
		$mission{Mission} = $mission;
		$mission{Target} = "$x:$y:$z";
		if ($12){
			$tick = $12;
		}elsif ($13){
			$eta += $13;
		}

		my ($planet_id) = $DBH->selectrow_array($findplanet,undef,$x,$y,$z,$ND::TICK);

		my $findtarget = $finddefensetarget;
		if ($mission eq 'Attack'){
			$findtarget = $findattacktarget;
		}elsif ($mission eq 'Defend'){
			$findtarget = $finddefensetarget;
		}

		$findtarget->execute($ND::UID,$tick,$planet_id);

		if ($findtarget->rows == 0){
			$mission{Warning} = "YOU DON'T HAVE A TARGET WITH THAT LANDING TICK";
		}elsif ($mission eq 'Attack'){
			my $claim = $findtarget->fetchrow_hashref;
			if ($claim->{launched}){
				$mission{Warning} = "Already launched on this target:$claim->{target},$claim->{wave},$claim->{launched}";
			}else{
				$addattackpoint->execute($ND::UID);
				$launchedtarget->execute($ND::UID,$claim->{target},$claim->{wave});
				$mission{Warning} = "OK:$claim->{target},$claim->{wave},$claim->{launched}";
				$LOG->execute($ND::UID,"Gave attack point for confirmation on $mission mission to $x:$y:$z, landing tick $tick");
			}
		}

		$addfleet->execute($ND::UID,$planet_id,$mission,$tick,$ND::UID,$eta);
		my $fleet = $DBH->last_insert_id(undef,undef,undef,undef,"fleets_id_seq");
		$mission{Fleet} = $fleet;
		my $ships = $10;
		my @ships;
		while ($ships =~ m/((?:\w+ )*\w+)\s+\w+\s+\w+\s+(?:Steal|Normal|Emp|Normal\s+Cloaked|Pod|Struc)\s+(\d+)/g){
			$addships->execute($fleet,$1,$2);
			push @ships,{Ship => $1, Amount => $2};
		}
		$mission{Ships} = \@ships;
		$LOG->execute($ND::UID,"Pasted confirmation for $mission mission to $x:$y:$z, landing tick $tick");
		push @missions,\%mission;
	}
	$DBH->commit;
	$BODY->param(Missions => \@missions);
}


1;
