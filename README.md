# NAME

javacgflow.pl - Convert Java call graph to Cflow-like text format

# SYNOPSIS

    javacgflow.pl [OPTIONS] TARGET.javacg-static ... >TARGET.flow
    Options:
        -f REGEX Specify a filter regex.
        -s REGEX Specify the start method.
        -r Print the flow from callee to caller (reverse direction).
        --help Print a brief help message and exit.
        --version Print the version number and exit.

# USAGE

    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static
    javacgflow.pl -f 'some.package' -s 'Servlet.doPost' TARGET.javacg-static

# REQUIRED ARGUMENTS

- `TARGET.javacg-static`

    Java call graph in the format produced by
    [java-callgraph](https://github.com/gousiosg/java-callgraph) static.

# OPTIONS

- `-f REGEX` Specify a filter regex.

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

- `-s REGEX` Specify the start method.

    Specify a Perl regular expression to select the start method for the call
    flow.
    Only methods matching this regex will be used as starting points in the call
    graph.

- `-r` Print the flow from callee to caller (reverse direction).

    By default the flow is printed from caller to callee, starting from methods
    that are never called by another method. With `-r`, the flow is inverted:
    it is printed from callee to caller, starting from methods that never call
    another method, and each indented line shows a method's callers instead of
    its callees.

- `--help` Print a brief help message and exit.
- `--version` Print the version number and exit.

# DESCRIPTION

This script converts a Java call graph in the format produced by
[java-callgraph](https://github.com/gousiosg/java-callgraph) static into a
Cflow-like text format.

# DIAGNOSTICS

- `Unknown option:`

    You specified an unknown option.
    Run the script with `--help` to see the available options.

- `invalid filter regex:`

    You specified an invalid filter regex.
    Run the script with `--help` to see the correct usage.

- `invalid start regex:`

    You specified an invalid start regex.
    Run the script with `--help` to see the correct usage.

- `, so couldn't print the flow`

    The script couldn't print due to output error.

- `, so couldn't print the help message:`

    The script couldn't print the help message due to output error.

# EXIT STATUS

The script exits with status 0 on success, and 1-255 if an error occurs.

# CONFIGURATION

This script does not use any configurations.

# DEPENDENCIES

- [java-callgraph](https://github.com/gousiosg/java-callgraph)
- [Perl](https://www.perl.org/)
- [Getopt::Std](https://perldoc.perl.org/Getopt/Std)
- [Carp](https://perldoc.perl.org/Carp)
- [English](https://perldoc.perl.org/English)
- [strict](https://perldoc.perl.org/strict)
- [warnings](https://perldoc.perl.org/warnings)

# INCOMPATIBILITIES

This script is compatible with Perl 5.26.3 and later.

# BUGS AND LIMITATIONS

Large graphs remain hard to read and may require additional filtering
or visualization tools.

# AUTHOR

Mitsutoshi NAKANO <ItSANgo@gmail.com>

# LICENSE AND COPYRIGHT

Copyright 2026 Mitsutoshi NAKANO

SPDX-License-Identifier: Apache-2.0
