#!/usr/bin/perl
#**************************************************************************
#   Copyright (C) 2006,2007 by Michael Andreen <harvATruinDOTnu>          *
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
use warnings;
no warnings 'exiting';
use CGI;
use DBI;
use DBD::Pg qw(:pg_types);
use LWP::Simple;
use lib qw{/var/www/ndawn/lib/};
use ND::DB;

our $dbh = ND::DB::DB();

#$dbh->trace("1","/tmp/scanstest");

#my $test = $dbh->prepare(q{INSERT INTO scans (tick,scan_id) VALUES(1,3) RETURNING id});
#print ;
$dbh->do(q{SET CLIENT_ENCODING TO 'LATIN1';});

my $scangroups = $dbh->prepare(q{SELECT id,scan_id,tick,uid FROM scans
	WHERE groupscan AND NOT parsed FOR UPDATE
});
my $oldscan = $dbh->prepare(q{SELECT scan_id FROM scans WHERE scan_id = ? AND tick >= tick() - 168});
my $addScan = $dbh->prepare(q{INSERT INTO scans (scan_id,tick,uid) VALUES (?,?,?)});
my $parsedscan = $dbh->prepare(q{UPDATE scans SET tick = ?, type = ?, planet = ?, parsed = TRUE WHERE id = ?});
my $addpoints = $dbh->prepare(q{UPDATE users SET scan_points = scan_points + ? WHERE uid = ? });
my $delscan = $dbh->prepare(q{DELETE FROM scans WHERE id = ?});

$scangroups->execute or die $dbh->errstr;

while (my $group = $scangroups->fetchrow_hashref){
	$dbh->begin_work;
	my $file = get("http://game.planetarion.com/showscan.pl?scan_grp=$group->{scan_id}");

	my $points = 0;
	while ($file =~ m/showscan.pl\?scan_id=(\d+)/g){
		unless ($dbh->selectrow_array($oldscan,undef,$1)){
			$addScan->execute($1,$group->{tick},$group->{uid});
			++$points;
		}
	}
	$addpoints->execute($points,$group->{uid});
	$parsedscan->execute($group->{tick},'GROUP',undef,$group->{id});
	$dbh->commit;
}

my $newscans = $dbh->prepare(q{SELECT id,scan_id,tick,uid FROM scans
	WHERE NOT groupscan AND NOT parsed FOR UPDATE
});
my $findplanet = $dbh->prepare(q{SELECT planetid(?,?,?,?)});
my $findoldplanet = $dbh->prepare(q{SELECT id FROM planet_stats WHERE x = $1 AND y = $2 AND z = $3 AND tick <= $4 ORDER BY tick DESC LIMIT 1});
my $findcoords = $dbh->prepare(q{SELECT * FROM planetcoords(?,?)});
my $addfleet = $dbh->prepare(q{INSERT INTO fleets (name,mission,sender,target,tick,eta,back,amount,ingal,uid) VALUES(?,?,?,?,?,?,?,?,?,-1) RETURNING id});
my $fleetscan = $dbh->prepare(q{INSERT INTO fleet_scans (id,scan) VALUES(?,?)});
my $addships = $dbh->prepare(q{INSERT INTO fleet_ships (id,ship,amount) VALUES(?,?,?)});
my $addpdata = $dbh->prepare(q{INSERT INTO planet_data (id,tick,scan,rid,amount) VALUES(?,?,?,(SELECT id FROM planet_data_types WHERE category = ? AND name = ?), ?)});

$dbh->begin_work or die 'No transaction';
$newscans->execute or die $dbh->errstr;
$dbh->pg_savepoint('scans') or die "No savepoint";

my %production = (None => 0, Low => 35, Medium => 65, High => 100);
while (my $scan = $newscans->fetchrow_hashref){
	$dbh->pg_release('scans') or die "Couldn't save";
	$dbh->pg_savepoint('scans') or die "Couldn't save";
	my $file = get("http://game.planetarion.com/showscan.pl?scan_id=$scan->{scan_id}");
	next unless defined $file;
	if ($file =~ /((?:\w| )*) (?:Scan|Probe) on (\d+):(\d+):(\d+) in tick (\d+)/){
		eval {
		my $type = $1;
		my $x = $2;
		my $y = $3;
		my $z = $4;
		my $tick = $5;

		if($dbh->selectrow_array(q{SELECT * FROM scans WHERE scan_id = ? AND tick = ? AND id <> ?},undef,$scan->{scan_id},$tick,$scan->{id})){
			$dbh->pg_rollback_to('scans') or die "rollback didn't work";
			$delscan->execute($scan->{id});
			$addpoints->execute(-1,$scan->{uid}) if $scan->{uid} > 0;
			die "Duplicate scan: $scan->{id} http://game.planetarion.com/showscan.pl?scan_id=$scan->{scan_id}\n";
		}
		my ($planet) = $dbh->selectrow_array($findplanet,undef,$x,$y,$z,$tick);
		unless ($planet){
			$dbh->pg_rollback_to('scans') or die "rollback didn't work";
			next;
		}
		my $scantext = "";
		if ($file =~ /(Note: [^<]*)/){
			#TODO: something about planet being closed?
		}
		if ($type eq 'Planet'){
			$file =~ s/(\d),(\d)/$1$2/g;
			while($file =~ m/"center">(Metal|Crystal|Eonium)\D+(\d+)\D+([\d,]+)/g){
				my ($roids,$res) = ($2,$3);
				$roids =~ s/,//g;
				$addpdata->execute($planet,$tick,$scan->{id}
					,'roid',$1, $roids) or die $dbh->errstr;
				$res =~ s/,//g;
				$addpdata->execute($planet,$tick,$scan->{id}
					,'resource',$1, $res) or die $dbh->errstr;
			}
			if($file =~ m{<td class="center">([A-Z][a-z]+)</td><td class="center">([A-Z][a-z]+)</td><td class="center">([A-Z][a-z]+)</td>}){
				$addpdata->execute($planet,$tick,$scan->{id}
					,'planet','Light Usage', $production{$1}) or die $dbh->errstr;
				$addpdata->execute($planet,$tick,$scan->{id}
					,'planet','Medium Usage', $production{$2}) or die $dbh->errstr;
				$addpdata->execute($planet,$tick,$scan->{id}
					,'planet','Heavy Usage', $production{$3}) or die $dbh->errstr;
			}
			if($file =~ m{<span class="superhighlight">([\d,]+)</span>}){
				my $res = $1;
				$res =~ s/,//g;
				$addpdata->execute($planet,$tick,$scan->{id}
					,'planet','Production', $res) or die $dbh->errstr;
			}
		}elsif ($type eq 'Jumpgate'){
		#print "$file\n";
			while ($file =~ m{(\d+):(\d+):(\d+)\D+(Attack|Defend|Return)</td><td class="left">([^<]*)\D+(\d+)\D+(\d+)}g){
				
				my ($sender) = $dbh->selectrow_array($findplanet,undef,$1,$2,$3,$tick) or die $dbh->errstr;
				($sender) = $dbh->selectrow_array($findoldplanet,undef,$1,$2,$3,$tick) if ((not defined $sender) && $4 eq 'Return');
				my $id = addfleet($5,$4,undef,$sender,$planet,$tick+$6,$6
					,undef,$7, $x == $1 && $y == $2);
				$fleetscan->execute($id,$scan->{id}) or die $dbh->errstr;
			}
		}elsif ($type eq 'News'){
			while( $file =~ m{top">((?:\w| )+)\D+(\d+)</td><td class="left" valign="top">(.+?)</td></tr>}g){
				my $news = $1;
				my $t = $2;
				my $text = $3;
				my ($x,$y,$z) = $dbh->selectrow_array($findcoords,undef,$planet,$t);
				die "No coords for: $planet tick $t" unless defined $x;
				if($news eq 'Launch' && $text =~ m/The (.*?) fleet has been launched, heading for (\d+):(\d+):(\d+), on a mission to (Attack|Defend). Arrival tick: (\d+)/g){
					my $eta = $6 - $t;
					my $mission = $5;
					my $back = $6 + $eta;
					$mission = 'AllyDef' if $eta == 6 && $x != $2;
					my ($target) = $dbh->selectrow_array($findplanet,undef
						,$2,$3,$4,$t) or die $dbh->errstr;
					die "No target: $2:$3:$4" unless defined $target;
					my $id = addfleet($1,$mission,undef,$planet,$target,$6
						,$eta,$back,undef, ($x == $2 && $y == $3));
					$fleetscan->execute($id,$scan->{id}) or die $dbh->errstr;
				}elsif($news eq 'Incoming' && $text =~ m/We have detected an open jumpgate from (.*?), located at (\d+):(\d+):(\d+). The fleet will approach our system in tick (\d+) and appears to have roughly (\d+) ships/g){
					my $eta = $5 - $t;
					my $mission = '';
					my $back = $5 + $eta;
					$mission = 'Defend' if $eta <= 6;
					$mission = 'AllyDef' if $eta == 6 && $x != $2;
					my ($target) = $dbh->selectrow_array($findplanet,undef
						,$2,$3,$4,$t) or die $dbh->errstr;
					die "No target: $2:$3:$4" unless defined $target;
					my $id = addfleet($1,$mission,undef,$target,$planet,$5
						,$eta,$back,$6, ($x == $2 && $y == $3));
					$fleetscan->execute($id,$scan->{id}) or die $dbh->errstr;
				}
			}
		} elsif($type eq 'Surface Analysis' || $type eq 'Technology Analysis'){
			my $cat = ($type eq 'Surface Analysis' ? 'struc' : 'tech');
			while($file =~ m{((?:[a-zA-Z]| )+)</t[dh]><td(?: class="right")?>(\d+)}sg){
				$addpdata->execute($planet,$tick,$scan->{id}
					,$cat,$1, $2) or die $dbh->errstr;
			}

		} elsif($type eq 'Unit' || $type eq 'Advanced Unit'){
			my $id = addfleet($type,'Full fleet',$file,$planet,undef,$tick,undef,undef,undef);
			$fleetscan->execute($id,$scan->{id}) or die $dbh->errstr;
		} elsif($type eq 'Incoming'){
			while($file =~ m{class="left">Fleet: (.*?)</td><td class="left">Mission: (\w+)</td></tr>(.*?)Total Ships: (\d+)}sg){
				my $id = addfleet($1,$2,$3,$planet,undef,$tick,undef,undef,$4);
				$fleetscan->execute($id,$scan->{id}) or die $dbh->errstr;
			}
		} else {
			print "Something wrong with scan $scan->{id} type $type at tick $tick http://game.planetarion.com/showscan.pl?scan_id=$scan->{scan_id}";
		}
		$parsedscan->execute($tick,$type,$planet,$scan->{id}) or die $dbh->errstr;
		#$dbh->rollback;
		};
		if ($@) {
			warn $@;
			$dbh->pg_rollback_to('scans') or die "rollback didn't work";
		}
	}else{
		warn "Nothing useful in scan: $scan->{id} http://game.planetarion.com/showscan.pl?scan_id=$scan->{scan_id}\n";
		$delscan->execute($scan->{id});
		$addpoints->execute(-1,$scan->{uid}) if $scan->{uid} > 0;
	}
}
#$dbh->rollback;
$dbh->commit;

sub addfleet {
	my ($name,$mission,$ships,$sender,$target,$tick,$eta,$back,$amount,$ingal) = @_;

	die "no sender" unless defined $sender;

	$ingal = 0 unless $ingal;
	$back = $tick + 4 if $ingal && $eta <= 4;

	if ($mission eq 'Return'){
		($sender,$target) = ($target,$sender);
		$back = $tick + $eta if $eta;
	}

	my @ships;
	my $total = 0;
	while(defined $ships && $ships =~ m{((?:[a-zA-Z]| )+)</td><td(?: class="right")?>(\d+)}sg){
		$total += $2;
		push @ships, [$1,$2];
	}
	$amount = $total if (!defined $amount) && defined $ships;
	my $id = $dbh->selectrow_array($addfleet,undef,$name,$mission,$sender
		,$target,$tick, $eta, $back, $amount,$ingal) or die $dbh->errstr;
	for my $s (@ships){
		unshift @{$s},$id;
		$addships->execute(@{$s}) or die $dbh->errstr;
	}
	return $id;
};
