#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Getopt::Std;

our $VERSION = '0.1.0';

## Default traversal depth when -d is not given.
## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
my $DEFAULT_DEPTH = 1000;
## use critic

##
# Generate a synthetic javacg-static call graph, used to benchmark
# javacgflow.pl's memory usage against javacgflow_iterative.pl at
# controlled traversal depths.
#
# Usage: generate_call_graph.pl [-s chain|fanout] [-d DEPTH] [-f FANOUT]
#
# -s chain (default): a single linear call chain
#   bench.M0 -> bench.M1 -> ... -> bench.M(DEPTH-1)
#   Depth-first traversal of this graph recurses DEPTH levels deep, which
#   is what stresses the difference between native recursion and an
#   explicit-stack traversal.
#
# -s fanout: a balanced tree of the given depth and fanout, e.g.
#   -f 2 -d 3 produces a small binary tree. Useful as a wide-but-shallow
#   counterpoint to the chain shape.
#
# Output is written to STDOUT in javacg-static format, one call edge per
# line: "M:CALLER (M)CALLEE".

getopts( 's:d:f:', \my %opts )
    or croak "usage: $PROGRAM_NAME [-s chain|fanout] [-d DEPTH] [-f FANOUT]";
my $shape  = $opts{s} // 'chain';
my $depth  = $opts{d} // $DEFAULT_DEPTH;
my $fanout = $opts{f} // 2;

##
# Format a synthetic method id as a javacg-static method string.
sub method_id {
    my ($n) = @_;
    return "bench.M$n:m()";
}

##
# Print one call edge line, or croak on an output error.
sub print_edge {
    my ( $caller, $callee ) = @_;
    say "M:$caller (M)$callee"
        or croak $OS_ERROR . ', so could not print the call graph';
    return;
}

if ( $shape eq 'chain' ) {
    for my $i ( 0 .. $depth - 2 ) {
        print_edge( method_id($i), method_id( $i + 1 ) );
    }
}
elsif ( $shape eq 'fanout' ) {
    my $next_id  = 1;
    my @frontier = (0);
    for ( 1 .. $depth ) {
        my @next_frontier;
        for my $parent (@frontier) {
            for ( 1 .. $fanout ) {
                my $child = $next_id;
                ++$next_id;
                print_edge( method_id($parent), method_id($child) );
                push @next_frontier, $child;
            }
        }
        @frontier = @next_frontier;
    }
}
else {
    croak "unknown -s shape: $shape (expected chain or fanout)";
}
