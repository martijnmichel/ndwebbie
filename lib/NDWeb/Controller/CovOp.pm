package NDWeb::Controller::CovOp;

use strict;
use warnings;
use parent 'Catalyst::Controller';

=head1 NAME

NDWeb::Controller::CovOp - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
	my ( $self, $c ) = @_;
	$c->stash( where => q{hack5 > 60000
		ORDER BY hack5 DESC, hack15 DESC, minalert
			,lastcovop NULLS FIRST,pstick DESC, dstick DESC,x,y,z
		});
	$c->forward('list');
}

sub easy : Local {
	my ( $self, $c ) = @_;
	$c->stash( where =>  q{minalert < 70
		ORDER BY minalert, max_bank_hack DESC, hack5 DESC, hack15 DESC
			,lastcovop NULLS FIRST,pstick DESC, dstick DESC,x,y,z
		});
	$c->forward('list');
}

sub distwhores : Local {
	my ( $self, $c ) = @_;
	$c->stash( where =>  q{distorters > 0
		ORDER BY distorters DESC, minalert
			,lastcovop NULLS FIRST,pstick DESC, dstick DESC,x,y,z
		});
	$c->forward('list');
}

sub marktarget : Local {
	my ( $self, $c, $target ) = @_;
	my $dbh = $c->model;
	my $update = $dbh->prepare(q{INSERT INTO covop_attacks (uid,id,tick) VALUES(?,?,tick())});
	eval{
		$update->execute($c->user->id,$target);
	};
	$c->forward('/redirect');
}

sub list : Private {
	my ( $self, $c ) = @_;
	my $dbh = $c->model;

	my $query = $dbh->prepare(q{
	SELECT * FROM (
		SELECT *
			,max_bank_hack(500000,500000,500000,pvalue,cvalue,5)
			,max_bank_hack(metal,crystal,eonium,pvalue,cvalue,5) AS hack5
			,max_bank_hack(metal,crystal,eonium,pvalue,cvalue,13) AS hack15
		FROM (SELECT p.id,coords(x,y,z),x,y,z,size
			,metal + metal_roids * (tick()-ps.tick) * 125 AS metal
			,crystal + crystal_roids * (tick()-ps.tick) * 125 AS crystal
			,eonium + eonium_roids * (tick()-ps.tick) * 125 AS eonium
			,distorters,guards
			,covop_alert(seccents,ds.total,size,guards,gov,0) AS minalert
			,covop_alert(seccents,ds.total,size,guards,gov,50) AS maxalert
			, planet_status, relationship,gov,ps.tick AS pstick, ds.tick AS dstick
			, p.value AS pvalue, c.value AS cvalue
			FROM current_planet_stats p
				LEFT OUTER JOIN current_planet_scans ps ON p.id = ps.planet
				LEFT OUTER JOIN current_development_scans ds ON p.id = ds.planet
				CROSS JOIN (SELECT value FROM current_planet_stats WHERE id = $1) c
			) AS foo
			LEFT OUTER JOIN (SELECT id,max(tick) AS lastcovop FROM covop_attacks
				GROUP BY id) co USING (id)
		WHERE (metal IS NOT NULL OR distorters IS NOT NULL)
			AND (NOT planet_status IN ('Friendly','NAP'))
			AND  (relationship IS NULL OR NOT relationship IN ('Friendly','NAP'))
	) a
	WHERE } . $c->stash->{where});
	$query->execute($c->user->planet);

	$c->stash(targets => $query->fetchall_arrayref({}));

	$c->stash(template => 'covop/index.tt2');
}
=head1 AUTHOR

Michael Andreen (harv@ruin.nu)

=head1 LICENSE

GPL 2.0, or later

=cut

1;
