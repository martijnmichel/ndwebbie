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
package ND::Web::Pages::EditRaid;
use strict;
use warnings FATAL => 'all';
use ND::Include;
use CGI qw/:standard/;
use ND::Web::Include;

$ND::PAGES{editRaid} = {parse => \&parse, process => \&process, render=> \&render};

sub parse {
	my ($uri) = @_;
	#if ($uri =~ m{^/.*/(\w+)$}){
	#	param('list',$1);
	#}
}

sub process {

}

sub render {
	my ($DBH,$BODY) = @_;
	my $error;

	$ND::TEMPLATE->param(TITLE => 'Create/Edit Raids');

	return $ND::NOACCESS unless isBC();

	my @alliances = alliances();
	$BODY->param(Alliances => \@alliances);

	my $raid;
	if (defined param 'raid' and param('raid') =~ /^(\d+)$/){
		my $query = $DBH->prepare(q{SELECT id,tick,waves,message,released_coords,open FROM raids WHERE id = ?});
		$raid = $DBH->selectrow_hashref($query,undef,$1);
	}
	if (defined param('cmd') && param('cmd') eq 'submit'){
		my $query = $DBH->prepare(q{INSERT INTO raids (tick,waves,message) VALUES(?,?,'')});
		if ($query->execute(param('tick'),param('waves'))){
			$raid = $DBH->last_insert_id(undef,undef,undef,undef,"raids_id_seq");
			my $query = $DBH->prepare(q{SELECT id,tick,waves,message,released_coords,open FROM raids WHERE id = ?});
			$raid = $DBH->selectrow_hashref($query,undef,$raid);
		}else{
			$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
		}
	}

	if ($raid && defined param('cmd')){
		if (param('cmd') eq 'remove'){
			$DBH->do(q{UPDATE raids SET open = FALSE, removed = TRUE WHERE id = ?},undef,$raid->{id});
		}elsif (param('cmd') eq 'Open'){
			if($DBH->do(q{UPDATE raids SET open = TRUE, removed = FALSE WHERE id = ?},undef,$raid->{id})){
				$raid->{open} = 1;
				$raid->{removed} = 0;
			}
		}elsif (param('cmd') eq 'Close'){
			if ($DBH->do(q{UPDATE raids SET open = FALSE WHERE id = ?},undef,$raid->{id})){
				$raid->{open} = 0;
			}
		}elsif (param('cmd') eq 'showcoords'){
			if($DBH->do(q{UPDATE raids SET released_coords = TRUE WHERE id = ?},undef,$raid->{id})){
				$raid->{released_coords} = 1;
			}
		}elsif (param('cmd') eq 'hidecoords'){
			if($DBH->do(q{UPDATE raids SET released_coords = FALSE WHERE id = ?},undef,$raid->{id})){
				$raid->{released_coords} = 0;
			}
		}elsif (param('cmd') eq 'comment'){
			$DBH->do(q{UPDATE raid_targets SET comment = ? WHERE id = ?}
				,undef,escapeHTML(param('comment')),param('target'))
				or $error .= p($DBH->errstr);

		}elsif (param('cmd') eq 'change'){
			$DBH->begin_work;
			my $message = escapeHTML(param('message'));
			$raid->{message} = $message;
			$raid->{waves} = param('waves');
			$raid->{tick} = param('tick');
			unless ($DBH->do(qq{UPDATE raids SET message = ?, tick = ?, waves = ? WHERE id = ?}
					,undef,$message,param('tick'),param('waves'),$raid->{id})){
				$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
			}
			my $sizelimit = '';
			if (param('sizelimit') =~ /^(\d+)$/){
				$sizelimit = "AND p.size >= $1";
				unless ($DBH->do(qq{DELETE FROM raid_targets WHERE id IN (SELECT t.id FROM current_planet_stats p 
						JOIN raid_targets t ON p.id = t.planet WHERE p.size < ? AND t.raid = ?)},undef,$1,$raid->{id})){
					$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
				}
			}
			my $targets = param('targets');
			my $addtarget = $DBH->prepare(qq{INSERT INTO raid_targets(raid,planet) (
				SELECT ?, id FROM current_planet_stats p WHERE x = ? AND y = ? AND COALESCE(z = ?,TRUE) $sizelimit)});
			while ($targets =~ m/(\d+):(\d+)(?::(\d+))?/g){
				unless ($addtarget->execute($raid->{id},$1,$2,$3)){
					$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
				}
			}
			if (param('alliance') =~ /^(\d+)$/ && $1 != 1){
				log_message $ND::UID,"BC adding alliance $1 to raid";
				my $addtarget = $DBH->prepare(qq{INSERT INTO raid_targets(raid,planet) (
					SELECT ?,id FROM current_planet_stats p WHERE alliance_id = ? $sizelimit)});
				unless ($addtarget->execute($raid->{id},$1)){
					$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
				}
			}
			my $groups = $DBH->prepare('SELECT gid,groupname FROM groups WHERE attack');
			my $delgroup = $DBH->prepare(q{DELETE FROM raid_access WHERE raid = ? AND gid = ?});
			my $addgroup = $DBH->prepare(q{INSERT INTO raid_access (raid,gid) VALUES(?,?)});
			$groups->execute();
			while (my $group = $groups->fetchrow_hashref){
				my $query;
				next unless defined param $group->{gid};
				if (param($group->{gid}) eq 'remove'){
					$query = $delgroup;
				}elsif(param($group->{gid}) eq 'add'){
					$query = $addgroup;
				}
				if ($query){
					unless ($query->execute($raid->{id},$group->{gid})){
						$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
					}
				}
			}
			unless ($DBH->commit){
				$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
			}
		}
	}
	if ($raid && param('removeTarget')){
		$error .= "test";
		unless($DBH->do(q{DELETE FROM raid_targets WHERE raid = ? AND id = ?}
				,undef,$raid->{id},param('removeTarget'))){
			$error .= "<p> Something went wrong: ".$DBH->errstr."</p>";
		}
	}

	my $groups = $DBH->prepare(q{SELECT g.gid,g.groupname,raid FROM groups g LEFT OUTER JOIN (SELECT gid,raid FROM raid_access WHERE raid = ?) AS ra ON g.gid = ra.gid WHERE g.attack});
	$groups->execute($raid ? $raid->{id} : undef);

	my @addgroups;
	my @remgroups;
	while (my $group = $groups->fetchrow_hashref){
		if ($group->{raid}){
			push @remgroups,{Id => $group->{gid}, Name => $group->{groupname}};
		}else{
			push @addgroups,{Id => $group->{gid}, Name => $group->{groupname}};
		}
	}
	$BODY->param(RemoveGroups => \@remgroups);
	$BODY->param(AddGroups => \@addgroups);


	if ($raid){

		$BODY->param(Raid => $raid->{id});
		if($raid->{open}){
			$BODY->param(Open => 'Close');
		}else{
			$BODY->param(Open => 'Open');
		}
		if($raid->{released_coords}){
			$BODY->param(ShowCoords => 'hidecoords');
			$BODY->param(ShowCoordsName => 'Hide');
		}else{
			$BODY->param(ShowCoords => 'showcoords');
			$BODY->param(ShowCoordsName => 'Show');
		}
		$BODY->param(Waves => $raid->{waves});
		$BODY->param(LandingTick => $raid->{tick});
		$BODY->param(Message => $raid->{message});

		my $order = "p.x,p.y,p.z";
		if (param('order') && param('order') =~ /^(score|size|value|xp|race)$/){
			$order = "$1 DESC";
		}

		my $targetquery = $DBH->prepare(qq{SELECT r.id,coords(x,y,z),raid,comment,size,score,value,race,planet_status AS planetstatus,relationship,comment
			FROM current_planet_stats p JOIN raid_targets r ON p.id = r.planet 
			WHERE r.raid = ?
			ORDER BY $order});
		$targetquery->execute($raid->{id}) or $error .= $DBH->errstr;
		my @targets;
		while (my $target = $targetquery->fetchrow_hashref){
			push @targets,$target;
		}
		$BODY->param(Targets => \@targets);
	}else{
		$BODY->param(Waves => 3);
		$BODY->param(LandingTick => $ND::TICK+12);
	}
	$BODY->param(Error => $error);
	return $BODY;
}

1;
