#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Getopt::Std;

##
# The version of this script.
# This is used for the --version option.
# @return The version string.
our $VERSION = '0.2.0';

##
# The help message string.
# The help message is printed when the script is run with the --help option.
# @return The help message string.
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
    -x REGEX Specify a regex for callees to exclude.
      A method is excluded from the output if it is called as a callee and
      matches REGEX. REGEX follows the same syntax rules as the -f REGEX.
      Defaults to \\A javax?[.], which excludes the java.* and javax.*
      packages.
    -r Print the flow from callee to caller (reverse direction).
example:
    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static
    $PROGRAM_NAME -f example.package -s Servlet.doPost TARGET.javacg-static

For more details run
    perldoc -F $PROGRAM_NAME
_END_OF_HELP_

##
# Print the help message.
# @return 1 if the help message was printed successfully, otherwise croak.
sub HELP_MESSAGE {
    return print "$help_message"
        or croak $OS_ERROR
        . qq{, so couldn't print the help message:\n}
        . $help_message;
}

##
# Parse a line of javacg-static output.
# @param[in] $line A line string of javacg-static output.
# @param[in] $exclude_regex
#   An optional regex matching callees to exclude. Defaults to
#   m/\A javax?[.]/xms, which excludes the java.* and javax.* packages.
# @return
#   ($caller, $callee)
#   if the line represents a call, otherwise undef.
sub parse_call_line {
    my ( $line, $exclude_regex ) = @_;
    $exclude_regex //= qr/\A javax?[.]/xms;
    if ( $line =~ /\A M:(\S+:\S+)\s+ [(].[)](\S+:\S+)/xms ) {
        my ( $caller, $callee ) = ( $1, $2 );
        return if $callee =~ $exclude_regex;
        return ( $caller, $callee );
    }
    return;
}

##
# Record a call edge from caller to callee in the state hash.
# Record the edge from caller to callee in the edges hash, and the reverse
# edge from callee to caller in the reversed_edges hash.
# @param[out] $state
#   A hash reference to store the state of the call graph.
#   The hash contains the following keys:
#   - edges: A hash reference to store the edges from caller to callee.
#     The keys are the caller method strings, and the values are hash
#     references where the keys are the callee method strings and the values
#     are the count of times the edge was recorded.
#   - called: A hash reference to store the count of times each method is
#     called.
#   - reversed_edges: A hash reference to store the edges from callee to
#     caller.
#     The keys are the callee method strings, and the values are hash
#     references where the keys are the caller method strings and the values
#     are the count of times the edge was recorded.
# @param[in] $caller
#   The caller method string in the format of javacg-static output.
# @param[in] $callee
#   The callee method string in the format of javacg-static output.
# @return
#   0 if the edge already exists, otherwise
#   > 0 if the edge was recorded successfully.
sub record_edge {
    my ( $state, $caller, $callee ) = @_;
    my $edges          = $state->{edges};
    my $called         = $state->{called};
    my $reversed_edges = $state->{reversed_edges};

    if ( exists $edges->{$caller}{$callee} ) { return 0 }
    ++$called->{$callee};
    $reversed_edges->{$callee}{$caller}
        = ( keys %{ $reversed_edges->{$callee} } ) + 1;
    return $edges->{$caller}{$callee} = ( keys %{ $edges->{$caller} } ) + 1;
}

##
# Load the javacg-static output and build the state.
# @param[in] $filter_regex
#   An optional regex to filter the methods to be included in the output.
# @param[in] $exclude_regex
#   An optional regex matching callees to exclude, passed through to
#   parse_call_line.
# @return A hash reference containing the state of the call graph.
sub load_javacg_static {
    my ( $filter_regex, $exclude_regex ) = @_;
    ## The state hash contains the edges, called, and reversed_edges hashes.
    # The edges hash stores the edges from caller to callee.
    # The called hash stores the count of times each method is called.
    # The reversed_edges hash stores the edges from callee to caller.
    my %state = (
        edges          => {},
        called         => {},
        reversed_edges => {},
    );

    while (<>) {
        chomp;
        ## Parse the line and get the caller and callee methods.
        my ( $caller, $callee ) = parse_call_line( $_, $exclude_regex );
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
# @return
#   The method string, possibly annotated with ' (recursive)' if recursion is
#   detected.
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
    foreach my $next_method (
        sort { $edges->{$method}{$a} <=> $edges->{$method}{$b} }
        keys %{ $edges->{$method} }
        )
    {
        depth_first_search( $edges, $next_method, $depth + 1, $visited );
    }
    delete $visited->{$method};
    return $method;
}

##
# Print the call flow starting from the specified methods.
# @param[in] $state
#   A hash reference containing the state of the call graph.
# @param[in] $start_regex
#   An optional regex to filter the starting methods.
# @param[in] $reverse
#   A boolean indicating whether to print the flow in reverse
#   (callee to caller).
# @return 1 if the flow was printed successfully, otherwise croak.
sub print_flow {
    my ( $state, $start_regex, $reverse ) = @_;

    # In reverse mode, walk reversed_edges (callee -> caller) instead of
    # edges (caller -> callee). The default starting points then become
    # methods that never call anything (leaves of the forward graph),
    # so $anchor swaps from "called" to "edges" to test for that.
    my $edges  = $reverse ? $state->{reversed_edges} : $state->{edges};
    my $anchor = $reverse ? $state->{edges}          : $state->{called};

    ## Determine the starting methods for the call flow.
    # If a start regex is provided, use it to filter the starting methods.
    # Otherwise, use methods that are not called by any other method
    # (or do not call any other method in reverse mode).
    my @starts;

    if ( defined $start_regex ) {
        for my $method ( sort { $a cmp $b } keys %{$edges} ) {
            if ( $method =~ $start_regex ) { push @starts, $method }
        }
    }
    else {
        for my $method ( sort { $a cmp $b } keys %{$edges} ) {
            if ( !exists $anchor->{$method} ) { push @starts, $method }
        }
    }

    ## Print the call flow starting from each of the starting methods.
    # Use a hash to track printed methods to avoid duplicate printing.
    foreach my $start (@starts) {
        ## A hash to track printed methods to avoid duplicate printing.
        # This is used to prevent printing the same method multiple times in
        # the flow.
        # The keys are the method strings, and the values are 1.
        my %printed;
        depth_first_search( $edges, $start, 0, \%printed );
    }
    return 1;
}

##
# Main function to execute the script.
# Parse command-line options using Getopt::Std.
# @return 1 if the script executed successfully, otherwise croak.
sub main {
    $Getopt::Std::STANDARD_HELP_VERSION = 1;
    ## The options are stored in the %opts hash.
    getopts( 'f:s:x:r', \my %opts ) or croak $help_message;

    ## Compile the start and filter regexes if provided, and handle errors.
    # The start regex is used to filter the starting methods for the call
    # flow.
    my $start_regex;
    if ( defined $opts{s} ) {
        eval { $start_regex = qr/$opts{s}/xms }
            or croak 'invalid start regex: ' . $opts{s} . "\n" . $EVAL_ERROR;
    }

    ## Compile the filter regex if provided, and handle errors.
    # The filter regex is used to filter the methods to be included in the
    # output.
    my $filter_regex;
    if ( defined $opts{f} ) {
        eval { $filter_regex = qr/$opts{f}/xms }
            or croak 'invalid filter regex: ' . $opts{f} . "\n" . $EVAL_ERROR;
    }

    ## Compile the exclude regex if provided, and handle errors.
    # The exclude regex is used to exclude callees from the call graph.
    # If not provided, parse_call_line falls back to its default, which
    # excludes the java.* and javax.* packages.
    my $exclude_regex;
    if ( defined $opts{x} ) {
        eval { $exclude_regex = qr/$opts{x}/xms }
            or croak 'invalid exclude regex: '
            . $opts{x} . "\n"
            . $EVAL_ERROR;
    }

    ## Load the javacg-static output and build the state of the call graph.
    # The state contains the edges, called, and reversed_edges hashes.
    # The edges hash stores the edges from caller to callee.
    # The called hash stores the count of times each method is called.
    # The reversed_edges hash stores the edges from callee to caller.
    # The state is then used to print the call flow starting from the
    # specified methods.
    my $state = load_javacg_static( $filter_regex, $exclude_regex );

    return print_flow( $state, $start_regex, $opts{r} );
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
        -x REGEX Specify a regex for callees to exclude.
        -r Print the flow from callee to caller (reverse direction).
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

=item * C<-x REGEX> Specify a regex for callees to exclude.

REGEX follows the same syntax rules as C<-f REGEX>.
A method is excluded from the output whenever it appears as a callee and
matches REGEX, regardless of whether it also appears as a caller elsewhere.
Defaults to C<\A javax?[.]>, which excludes the C<java.*> and C<javax.*>
packages.
Pass a REGEX that never matches (such as C<(?!)>) to disable exclusion
entirely.

=item * C<-r> Print the flow from callee to caller (reverse direction).

By default the flow is printed from caller to callee, starting from methods
that are never called by another method. With C<-r>, the flow is inverted:
it is printed from callee to caller, starting from methods that never call
another method, and each indented line shows a method's callers instead of
its callees.

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

=item * C<invalid exclude regex:>

You specified an invalid exclude regex.
Run the script with C<--help> to see the correct usage.

=item * C<, so couldn't print the flow>

The script couldn't print due to output error.

=item * C<, so couldn't print the help message:>

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
