#!/usr/bin/perl

# Mocksock: A tool for simulating the traffic of a TCP server or client.
#
# Copyright 2020 Ericsson Software Technology <viktor.soderqvist@est.tech>
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

use strict;
use warnings;
use Socket;

#print (escape(unescape(escape("hello\r\nwho\tare\eyou?\n"))), "\n");
#exit;

my $role = "server";
my $port = 4444;
my $host = "localhost"; # used for client only
my $debug = 0;

# Parse command line args
while ($_ = shift) {
    if (/^(?:-p|--port)$/) {
        $port = shift;
        die "Bad port $port\n" unless $port > 0;
    } elsif (/^(?:-c|--client)$/) {
        $role = "client";
    } elsif (/^--host$/) {
        $host = shift;
        die "Bad host $host\n" unless $host;
    } elsif (/^(?:-d|--debug)$/) {
        $debug = 1;
    } elsif (/^(?:-h|--help)$/) {
        print "Usage: $0 [ -p PORT ] [ OPTIONS... ] \n";
        print "\n";
        print "Acts as a TCP server, accepting a single peer.\n";
        print "TODO: Document options. (E.g. -c means act as client instead of server.)\n";
        print "\n";
        print "Commands are expected on stdin, one per line. Embedded newlines\n";
        print "and other special characters can be used using escapes \\r, \\n,\n";
        print "etc. Commands:\n\n";
        print "  * SEND data\n";
        print "        Send the data to the peer.\n";
        print "  * RECV data\n";
        print "        Receive the expected data from the peer.\n";
        print "  * CLOSE\n";
        print "        Close the socket to the peer.\n";
        print "  * PEER CLOSE\n";
        print "        Wait for the peer to close the connection.\n";
        exit;
    } else {
        die "Bad option $_\n";
    }
}

my $listener;   # Listener socket (server only)
my $connection; # Connection socket (client and server)

END {
    close $listener if $listener;
}

if ($role eq "server") {
    socket(my $listener, PF_INET, SOCK_STREAM, getprotobyname("tcp"))
        or die "socket: $!\n";
    setsockopt($listener, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
        or die "setsockopt: $!\n";
    bind($listener, sockaddr_in($port, INADDR_ANY))
        or die "bind: $!\n";
    listen($listener, 1)
        or die "listen: $!\n";
    print "Server started on port $port\n" if $debug;
    my $peer_addr = accept($connection, $listener);
    my($client_port, $client_addr) = sockaddr_in($peer_addr);
    my $name = gethostbyaddr($client_addr, AF_INET);
    print "Accepted connection from $name [", inet_ntoa($client_addr), "]",
        " on client port $client_port\n" if $debug;
} elsif ($role eq "client") {
    socket($connection, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2])
        or die "socket: $!\n";
    connect($connection, pack_sockaddr_in($port, inet_aton($host)))
        or die "connect: $!\n";
    print "Client connected to $host:$port\n" if $debug;
} else {
    die "Unexpected role $role\n";
}

# Loop over commands on stdin.
while (<>) {
    print "Command for $role: $_" if $debug;
    if (/^SEND (.*)/) {
        my $data = unescape($1);
        print $connection $data;
        flush $connection;
    } elsif (/^RECV (.*)/) {
        my $data = unescape($1);
        my $bytes_total = length $data;
        my $bytes_read = 0;
        for (my $offset = 0; $offset < $bytes_total; $offset += $bytes_read) {
            my $buffer;
            $bytes_read = read $connection, $buffer, $bytes_total - $offset;
            print "$role received $bytes_read at offset $offset of $bytes_total in '$1'\n" if $debug;
            if ($bytes_read == 0) {
                die "Unexpected EOF\n";
            }
            if ($buffer ne substr($data, $offset, $bytes_read)) {
                die "Unexpected data received: " . escape($buffer) . "\n";
            }
        }
    } elsif (/^SLEEP (\d+)$/) {
        sleep $1;
    } elsif (/^CLOSE$/) {
        close $connection;
    } elsif (/^PEER CLOSED?$/) {
        my $buffer;
        my $bytes_read = read $connection, $buffer, 1;
        die "Data received from peer when closing is expected\n" if $bytes_read;
    } else {
        die "Unexpected command: $_\n";
    }
}
exit;

sub escape_char {
    $_ = shift;
    return "\\r" if /\r/; # nicer than \x0d, etc.
    return "\\n" if /\n/;
    return "\\t" if /\t/;
    return "\\\\" if /\\/;
    return sprintf "\\x%02x", ord $_;
}
sub escape {
    $_ = shift;
    s/([^A-Za-z0-9\/\-_.,:;!?~\*'"()\^\$])/ escape_char $1 /eg;
    return $_;
}
sub unescape {
    $_ = shift;
    s/\\([tnrfbae\\]|x\{[0-9a-fA-F]+\}|x[0-9a-fA-F]{1,2}|0[0-7]{0,2})/eval "\"\\$1\""/eg;
    return $_;
}
