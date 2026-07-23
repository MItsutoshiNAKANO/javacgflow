#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Getopt::Std;

our $VERSION = '0.0.1';

my $help_message = <<"_END_OF_HELP_";
Usage: $PROGRAM_NAME [OPTIONS] TARGET.javacg-static ...
Convert Java call graph to Cflow like text.
Options:
    -f REGEX Specify a filter regex.
      REGEX is a Perl regular expression to filter the methods to be included
      in the output.
      REGEX is applied to both the caller and callee methods, and a method
      is included in the output if either the caller or callee matches
      the REGEX.
      REGEX is applied to the full method name, including the class name and
      the method signature, in the format of javacg-static output.
      REGEX is case-sensitive by default, but you can use the (?i) modifier to
      make it case-insensitive.
      REGEX style is Perl regular expression syntax, so you can use any valid
      Perl regex syntax, including character classes, quantifiers, anchors,
      and so on.
      REGEX modifiers are /xms by default, so you can use whitespace
      and comments in your regex, and the dot (.) matches any character.
    -s REGEX Specify the start method.
example:
    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static
    $PROGRAM_NAME -f example.package -s Servlet.doPost TARGET.javacg-static 

For more details run
    perldoc -F $PROGRAM_NAME
_END_OF_HELP_

##
# Print the help message.
sub HELP_MESSAGE {
    print "$help_message"
        or croak $OS_ERROR . q{, so couldn't print the help message};
    return $help_message;
}

##
# Parse a line of javacg-static output.
# @param[in] $line A line string of javacg-static output.
# @return
#   ($caller, $callee)
#   if the line represents a call, otherwise undef.
sub parse_call_line {
    my ($line) = @_;
    if ( $line =~ /\A M:(\S+:\S+)\s+ [(].[)](\S+:\S+)/xms ) {
        my ( $caller, $callee ) = ( $1, $2 );
        return if $callee =~ m/\Ajavax?[.]/xms;
        return ( $caller, $callee );
    }
    return;
}

##
# Record the edge from caller to callee in the edges hash.
# @param[out] $state
#   A hash reference to store the state of the call graph.
# @param[in] $caller
#   The caller method string in the format of javacg-static output.
# @param[in] $callee
#   The callee method string in the format of javacg-static output.
# @return
#   0 if the edge already exists, otherwise
#   > 0 if the edge was recorded successfully.
sub record_edge {
    my ( $state, $caller, $callee ) = @_;
    my $edges  = $state->{edges};
    my $called = $state->{called};
    if ( exists $edges->{$caller}{$callee} ) { return 0 }
    ++$called->{$callee};
    return $edges->{$caller}{$callee} = keys %{ $edges->{$caller} };
}

##
# Load the javacg-static output and build the state.
# @param[in] $filter_regex
#   An optional regex to filter the methods to be included in the output.
# @return A hash reference containing the state of the call graph.
sub load_javacg_static {
    my ($filter_regex) = @_;
    my %state = (
        edges  => {},
        called => {}
    );

    while (<>) {
        chomp;
        my ( $caller, $callee ) = parse_call_line($_);
        next if !defined $caller;
        next
            if defined $filter_regex
            && $caller !~ $filter_regex
            && $callee !~ $filter_regex;
        record_edge( \%state, $caller, $callee );
    }
    return \%state;
}

##
# Perform a depth-first search to print the call flow.
# @param[in] $edges
#   A hash reference containing the edges of the call graph.
# @param[in] $method
#   The current method string in the format of javacg-static output.
# @param[in] $depth
#   The current depth of the search, used for indentation.
# @param[in,out] $visited
#   A hash reference tracking the ancestors on the current path, to detect
#   recursion. Mutated in place rather than copied, and restored to its
#   original contents before returning.
# @return None.
sub depth_first_search {
    my ( $edges, $method, $depth, $visited ) = @_;
    print q{  } x $depth . $method
        or croak $OS_ERROR . q{, so couldn't print the flow};
    if ( exists $visited->{$method} ) {
        say '(recursive)'
            or croak $OS_ERROR . q{, so couldn't print the flow};
        return $method . ' (recursive)';
    }
    say q{} or croak $OS_ERROR . q{, so couldn't print the flow};
    ++$visited->{$method};
    for my $callee (
        sort { $edges->{$method}{$a} <=> $edges->{$method}{$b} }
        keys %{ $edges->{$method} }
        )
    {
        depth_first_search( $edges, $callee, $depth + 1, $visited );
    }
    delete $visited->{$method};
    return $method;
}

sub print_flow {
    my ( $state, $start_regex ) = @_;
    my $edges  = $state->{edges};
    my $called = $state->{called};

    my @starts;

    if ( defined $start_regex ) {
        for my $method ( sort { $a cmp $b } keys %{$edges} ) {
            if ( $method =~ $start_regex ) { push @starts, $method }
        }
    }
    else {
        for my $method ( sort { $a cmp $b } keys %{$edges} ) {
            if ( !exists $called->{$method} ) { push @starts, $method }
        }
    }

    foreach my $start (@starts) {
        my %printed;
        depth_first_search( $edges, $start, 0, \%printed );
    }
    return 1;
}

##
# Main function to execute the script.
# @return 1 if the script executed successfully, otherwise croak.
sub main {
    $Getopt::Std::STANDARD_HELP_VERSION = 1;
    getopts( 'f:s:', \my %opts ) or croak $help_message;
    my $start_regex;
    if ( defined $opts{s} ) {
        eval { $start_regex = qr/$opts{s}/xms }
            or croak 'invalid start regex: ' . $opts{s} . "\n" . $EVAL_ERROR;
    }
    my $filter_regex;
    if ( defined $opts{f} ) {
        eval { $filter_regex = qr/$opts{f}/xms }
            or croak 'invalid filter regex: ' . $opts{f} . "\n" . $EVAL_ERROR;
    }

    my $state = load_javacg_static($filter_regex);

    return print_flow( $state, $start_regex );
}

if ( !caller ) { main() }

1;

__END__

=encoding utf8

=head1 NAME

javacgflow.pl - Convert Java call graph to Cflow-like text format

=head1 SYNOPSIS

    javacgflow.pl [OPTIONS] TARGET.javacg-static ... >TARGET.flow
    Options:
        -f REGEX Specify a filter regex.
        -s REGEX Specify the start method.
        --help Print a brief help message and exit.
        --version Print the version number and exit.

=head1 USAGE

    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static
    javacgflow.pl -f 'some.package' -s 'Servlet.doPost' TARGET.javacg-static

=head1 REQUIRED ARGUMENTS

=over

=item * F<TARGET.javacg-static>

Java call graph in the format produced by
L<java-callgraph|https://github.com/gousiosg/java-callgraph> static.

=back

=head1 OPTIONS

=over

=item * C<-f REGEX> Specify a filter regex.

REGEX is a Perl regular expression to filter the methods to be included in the
output.
REGEX is applied to both the caller and callee methods, and a method is
included in the output if either the caller or callee matches the REGEX.
REGEX is applied to the full method name, including the class name and the
method signature, in the format of javacg-static output.
REGEX is case-sensitive by default, but you can use the (?i) modifier to make
it case-insensitive.
REGEX style is Perl regular expression syntax, so you can use any valid Perl
regex syntax, including character classes, quantifiers, anchors, and so on.
REGEX modifiers are /xms by default, so you can use whitespace and comments in
your regex, and the dot (.) matches any character.

=item * C<-s REGEX> Specify the start method.

Specify a Perl regular expression to select the start method for the call
flow.
Only methods matching this regex will be used as starting points in the call
graph.

=item * C<--help> Print a brief help message and exit.

=item * C<--version> Print the version number and exit.

=back

=head1 DESCRIPTION

This script converts a Java call graph in the format produced by
L<java-callgraph|https://github.com/gousiosg/java-callgraph> static into a
Cflow-like text format.

=head1 DIAGNOSTICS

=over

=item * C<Unknown option:>

You specified an unknown option.
Run the script with C<--help> to see the available options.

=item * C<invalid filter regex:>

You specified an invalid filter regex.
Run the script with C<--help> to see the correct usage.

=item * C<invalid start regex:>

You specified an invalid start regex.
Run the script with C<--help> to see the correct usage.

=item * C<, so couldn't print the flow>

The script couldn't print due to output error.

=item * C<, so couldn't print the help message>

The script couldn't print the help message due to output error.

=back

=head1 EXIT STATUS

The script exits with status 0 on success, and 1-255 if an error occurs.

=head1 CONFIGURATION

This script does not use any configurations.

=head1 DEPENDENCIES

=over

=item * L<java-callgraph|https://github.com/gousiosg/java-callgraph>

=item * L<Perl|https://www.perl.org/>

=item * L<Getopt::Std|https://perldoc.perl.org/Getopt/Std>

=item * L<Carp|https://perldoc.perl.org/Carp>

=item * L<English|https://perldoc.perl.org/English>

=item * L<strict|https://perldoc.perl.org/strict>

=item * L<warnings|https://perldoc.perl.org/warnings>

=back

=head1 INCOMPATIBILITIES

This script is compatible with Perl 5.26.3 and later.

=head1 BUGS AND LIMITATIONS

Large graphs remain hard to read and may require additional filtering
or visualization tools.

=head1 AUTHOR

Mitsutoshi NAKANO <ItSANgo@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright 2026 Mitsutoshi NAKANO

SPDX-License-Identifier: Apache-2.0
