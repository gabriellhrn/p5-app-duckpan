package App::DuckPAN::Lookup::Util;
# ABSTRACT: Utilities for standardized lookups.

BEGIN {
	require Exporter;

	our @ISA = qw(Exporter);

	our @EXPORT_OK = qw(lookup);
}

use List::Util qw(pairs);
use List::MoreUtils qw(uniq);

sub satisfy {
	my ($parent, $by, $lookup) = @_;
	return $by->($parent, $lookup) if ref $by eq 'CODE';
	my $pby = ref $parent eq 'HASH'
		? $parent->{$by} : $parent->$by;
	ref $lookup eq 'CODE' ? $lookup->($pby) : $pby eq $lookup;
}

sub lookup {
	my ($lookup_vals, @lookups) = @_;
	my @results = uniq @$lookup_vals;
	foreach (pairs @lookups) {
		return () unless @results;
		my ($by, $lookup) = @$_;
		@results = grep { satisfy($_, $by, $lookup) } @results;
	}
	return @results;
}

1;

__END__