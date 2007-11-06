#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use DBD::Pg qw(:pg_types);

use LWP::Simple;

our $dbh;
for my $file ("/home/whale/db.pl")
{
	unless (my $return = do $file){
		warn "couldn't parse $file: $@" if $@;
		warn "couldn't do $file: $!"    unless defined $return;
		warn "couldn't run $file"       unless $return;
	}
}

$dbh->trace("0","/tmp/scanstest");
my $update = $dbh->prepare("UPDATE users SET hostmask = pnick || '.users.netgamers.org' where hostmask ilike '%.%' AND NOT hostmask ilike pnick || '.users.netgamers.org'");
$update->execute();
$dbh->disconnect;