#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English    qw(-no_match_vars);
use File::Temp qw(tempfile);
use FindBin    qw($Bin);
use Test::More;

our $VERSION = '0.1.0';

## no critic (Modules::RequireBarewordIncludes)
# javacgflow.pl is a script, not an installed module, so it cannot be
# required by bareword name; it is loaded by path instead.
require "$Bin/../javacgflow.pl";
## use critic

##
# Run $code with STDOUT redirected to a string, and return that string.
sub capture_stdout {
    my ($code) = @_;
    my $buf = q{};
    open my $fh, '>', \$buf or croak $OS_ERROR;
    ## no critic (InputOutput::ProhibitOneArgSelect)
    my $old_fh = select $fh;
    my $ok     = eval { $code->(); 1 };
    my $err    = $EVAL_ERROR;
    select $old_fh;
    ## use critic
    close $fh or croak $OS_ERROR;
    if ( !$ok ) { croak $err }
    return $buf;
}

##
# Write @lines to a temporary file and return its path.
sub fixture_file {
    my (@lines) = @_;
    my ( $fh, $filename ) = tempfile();
    for my $line (@lines) {
        print {$fh} "$line\n" or croak $OS_ERROR;
    }
    close $fh or croak $OS_ERROR;
    return $filename;
}

subtest 'HELP_MESSAGE' => sub {
    my $out = capture_stdout( \&HELP_MESSAGE );
    like( $out, qr/\AUsage:/xms,    'prints a usage line' );
    like( $out, qr/-f \s REGEX/xms, 'documents the -f option' );
    like( $out, qr/-s \s REGEX/xms, 'documents the -s option' );
    like( $out, qr/-r \s Print/xms, 'documents the -r option' );
    return;
};

subtest 'parse_call_line' => sub {
    my @caller_callee = parse_call_line('M:pkg.A:foo() (M)pkg.B:bar()');
    is_deeply(
        \@caller_callee,
        [ 'pkg.A:foo()', 'pkg.B:bar()' ],
        'extracts caller and callee from a valid call line'
    );

    my @not_a_call = parse_call_line('not a call line');
    is( scalar @not_a_call, 0,
        'returns nothing for a non-matching line' );

    my @java_callee
        = parse_call_line('M:pkg.A:foo() (M)java.lang.String:valueOf()');
    is( scalar @java_callee,
        0, 'filters out callees in the java.* package' );

    my @javax_callee
        = parse_call_line('M:pkg.A:foo() (M)javax.swing.JFrame:<init>()');
    is( scalar @javax_callee,
        0, 'filters out callees in the javax.* package' );

    return;
};

subtest 'record_edge' => sub {
    my %state = ( edges => {}, called => {}, reversed_edges => {} );

    is( record_edge( \%state, 'C:caller()', 'X:first()' ),
        0, 'first edge from a caller is recorded with rank 0' );
    is( record_edge( \%state, 'C:caller()', 'Y:second()' ),
        1, 'second edge from the same caller gets the next rank' );
    is( record_edge( \%state, 'C:caller()', 'X:first()' ),
        0, 'recording the same edge again reports it as already known' );
    is( $state{edges}{'C:caller()'}{'X:first()'}, 0,
        'regression: re-recording the rank-0 edge must not overwrite its rank'
    );
    is( record_edge( \%state, 'C:caller()', 'Z:third()' ),
        2, 'regression: the next new edge must not collide with rank 0' );
    is( $state{called}{'X:first()'},
        1,
        'a duplicate edge does not double-count the callee as called' );
    is_deeply(
        $state{reversed_edges},
        {   'X:first()'  => { 'C:caller()' => 0 },
            'Y:second()' => { 'C:caller()' => 0 },
            'Z:third()'  => { 'C:caller()' => 0 },
        },
        'records the reverse edge from each callee back to its caller'
    );

    return;
};

subtest 'load_javacg_static' => sub {
    my $file = fixture_file(
        'M:pkg.A:foo() (M)pkg.B:bar()',
        'M:pkg.A:foo() (M)pkg.C:baz()',
        'M:pkg.B:bar() (M)pkg.C:baz()',
        'M:pkg.A:foo() (M)java.lang.String:valueOf()',
        'not a call line',
    );

    subtest 'without a filter' => sub {
        local @ARGV = ($file);
        my $state = load_javacg_static(undef);
        is_deeply(
            $state->{edges},
            {   'pkg.A:foo()' =>
                    { 'pkg.B:bar()' => 0, 'pkg.C:baz()' => 1 },
                'pkg.B:bar()' => { 'pkg.C:baz()' => 0 },
            },
            'records every edge in call order, skipping invalid and java.* lines'
        );
        is_deeply(
            $state->{called},
            { 'pkg.B:bar()' => 1, 'pkg.C:baz()' => 2 },
            'counts how many times each callee is called'
        );
        is_deeply(
            $state->{reversed_edges},
            {   'pkg.B:bar()' => { 'pkg.A:foo()' => 0 },
                'pkg.C:baz()' =>
                    { 'pkg.A:foo()' => 0, 'pkg.B:bar()' => 1 },
            },
            'records every edge in reverse, callee to caller'
        );
        return;
    };

    subtest 'with a filter regex' => sub {
        local @ARGV = ($file);
        my $state = load_javacg_static(qr/pkg[.]B/xms);
        is_deeply(
            $state->{edges},
            {   'pkg.A:foo()' => { 'pkg.B:bar()' => 0 },
                'pkg.B:bar()' => { 'pkg.C:baz()' => 0 },
            },
            'keeps only lines where the caller or callee matches the filter'
        );
        return;
    };

    return;
};

subtest 'depth_first_search' => sub {
    my %edges = (
        'A:a()' => { 'B:b()' => 0, 'C:c()' => 1 },
        'B:b()' => {},
        'C:c()' => { 'A:a()' => 0 },
    );

    my %visited;
    my $out = capture_stdout(
        sub { depth_first_search( \%edges, 'A:a()', 0, \%visited ) } );
    is( $out,
        "A:a()\n  B:b()\n  C:c()\n    A:a()(recursive)\n",
        'indents by depth, visits callees in rank order, and marks a cycle back to an ancestor as recursive'
    );
    is_deeply( \%visited, {},
        'the ancestor-tracking hash is restored to its original contents after the traversal completes'
    );

    return;
};

subtest 'print_flow' => sub {
    my %state = (
        edges => {
            'A:a()' => { 'B:b()' => 0 },
            'B:b()' => { 'C:c()' => 0 },
            'C:c()' => {},
            'D:d()' => {},
        },
        called => { 'B:b()' => 1, 'C:c()' => 1 },
    );

    subtest 'default: starts from methods that are never called' => sub {
        my $out = capture_stdout( sub { print_flow( \%state, undef ) } );
        is( $out,
            "A:a()\n  B:b()\n    C:c()\nD:d()\n",
            'prints one tree per uncalled method, in alphabetical order'
        );
        return;
    };

    subtest 'with a start regex' => sub {
        my $out
            = capture_stdout( sub { print_flow( \%state, qr/\AB/xms ) } );
        is( $out,
            "B:b()\n  C:c()\n",
            'starts only from methods matching the regex'
        );
        return;
    };

    return;
};

subtest 'print_flow (reverse)' => sub {
    my %state = (
        edges => {
            'A:a()' => { 'B:b()' => 0 },
            'B:b()' => { 'C:c()' => 0 },
        },
        called         => { 'B:b()' => 1, 'C:c()' => 1 },
        reversed_edges => {
            'B:b()' => { 'A:a()' => 0 },
            'C:c()' => { 'B:b()' => 0 },
        },
    );

    subtest 'default: starts from methods that never call anything' =>
        sub {
            my $out
            = capture_stdout( sub { print_flow( \%state, undef, 1 ) } );
            is( $out,
                "C:c()\n  B:b()\n    A:a()\n",
            'walks callee to caller, starting from the leaf of the forward graph'
            );
            return;
        };

    subtest 'with a start regex' => sub {
        my $out
            = capture_stdout( sub { print_flow( \%state, qr/\AB/xms, 1 ) } );
        is( $out,
            "B:b()\n  A:a()\n",
            'starts only from methods matching the regex'
        );
        return;
    };

    return;
};

subtest 'main (end to end)' => sub {
    my $file = fixture_file(
        'M:pkg.A:foo() (M)pkg.B:bar()',
        'M:pkg.B:bar() (M)pkg.C:baz()',
    );

    local @ARGV = ( '-s', 'pkg.A', $file );
    my $out = capture_stdout( sub { main() } );
    is( $out,
        "pkg.A:foo()\n  pkg.B:bar()\n    pkg.C:baz()\n",
        'wires option parsing, loading, and printing together'
    );

    return;
};

subtest 'main (end to end, reverse)' => sub {
    my $file = fixture_file(
        'M:pkg.A:foo() (M)pkg.B:bar()',
        'M:pkg.B:bar() (M)pkg.C:baz()',
    );

    local @ARGV = ( '-r', $file );
    my $out = capture_stdout( sub { main() } );
    is( $out,
        "pkg.C:baz()\n  pkg.B:bar()\n    pkg.A:foo()\n",
        'wires the -r option through to print the flow from callee to caller'
    );

    return;
};

subtest 'main: error handling' => sub {
    my $file = fixture_file('M:pkg.A:foo() (M)pkg.B:bar()');

    subtest 'invalid filter regex' => sub {
        local @ARGV = ( '-f', '(', $file );
        my $ok = eval { main(); 1 };
        ok( !$ok, 'main() dies' );
        like(
            $EVAL_ERROR,
            qr/\Ainvalid \s filter \s regex:/xms,
            'dies with a diagnostic naming the bad -f regex'
        );
        return;
    };

    subtest 'invalid start regex' => sub {
        local @ARGV = ( '-s', '(', $file );
        my $ok = eval { main(); 1 };
        ok( !$ok, 'main() dies' );
        like(
            $EVAL_ERROR,
            qr/\Ainvalid \s start \s regex:/xms,
            'dies with a diagnostic naming the bad -s regex'
        );
        return;
    };

    subtest 'unknown option' => sub {
        local @ARGV = ( '-z', $file );
        my $ok = eval { main(); 1 };
        ok( !$ok, 'main() dies' );
        like( $EVAL_ERROR, qr/\AUsage:/xms,
            'dies with the help message' );
        return;
    };

    return;
};

subtest 'main: --help and --version' => sub {
    my $script = "$Bin/../javacgflow.pl";

    subtest '--help' => sub {
        ## no critic (InputOutput::ProhibitBacktickOperators)
        my $out = qx{$EXECUTABLE_NAME $script --help 2>/dev/null};
        ## use critic
        is( $CHILD_ERROR, 0, 'exits successfully' );
        like(
            $out,
            qr/javacgflow[.]pl \s version/xms,
            'prints the Getopt::Std diagnostic banner'
        );
        like( $out, qr/Usage:/xms, 'prints the usage message' );
        return;
    };

    subtest '--version' => sub {
        ## no critic (InputOutput::ProhibitBacktickOperators)
        my $out = qx{$EXECUTABLE_NAME $script --version 2>/dev/null};
        ## use critic
        is( $CHILD_ERROR, 0, 'exits successfully' );
        like(
            $out,
            qr/javacgflow[.]pl \s version \s $VERSION/xms,
            'prints the version banner'
        );
        unlike( $out, qr/Usage:/xms,
            'does not also print the usage message' );
        return;
    };

    return;
};

subtest 'regression: no two callees of the same caller share a rank' => sub {
    local @ARGV = ("$Bin/commons-cli.javacg-static");
    my $state = load_javacg_static(undef);

    my @collisions;
    for my $caller ( keys %{ $state->{edges} } ) {
        my %seen_rank;
        for my $callee ( keys %{ $state->{edges}{$caller} } ) {
            my $rank = $state->{edges}{$caller}{$callee};
            if ( $seen_rank{$rank}++ ) {
                push @collisions, "$caller -> $callee (rank $rank)";
            }
        }
    }
    is_deeply( \@collisions, [],
        'every callee of a given caller gets a unique rank, even with duplicate call sites in the input'
    );

    return;
};

done_testing();
