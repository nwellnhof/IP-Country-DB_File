package IP::Country::DB_File;

use strict;
use vars qw($VERSION);

use DB_File ();
use Fcntl ();
use Socket ();

BEGIN {
    $VERSION = '2.00';
}

sub new {
    my ($class, $db_file) = @_;
    $db_file = 'ipcc.db' unless defined($db_file);

    my $this = {};
    my %db;

    $this->{db} = tie(%db, 'DB_File', $db_file, Fcntl::O_RDONLY, 0666,
                      $DB_File::DB_BTREE)
        or die("Can't open database $db_file: $!");
    
    return bless($this, $class);
}

sub inet_ntocc {
    my ($this, $addr) = @_;
    
    my ($key, $data);
    $this->{db}->seq($key = $addr, $data, DB_File::R_CURSOR()) == 0
        or return undef;
    my $start = substr($data, 0, 4);
    my $cc    = substr($data, 4, 2);
    
    return $addr ge $start ? $cc : undef;
}

sub inet_atocc {
    my ($this, $ip) = @_;
    
    my $addr = Socket::inet_aton($ip);
    return undef unless defined($addr);
    
    my ($key, $data);
    $this->{db}->seq($key = $addr, $data, DB_File::R_CURSOR()) == 0
        or return undef;
    my $start = substr($data, 0, 4);
    my $cc    = substr($data, 4, 2);
    
    return $addr ge $start ? $cc : undef;
}

sub db_time {
    my $this = shift;
    
    my $file;
    my $fd = $this->{db}->fd();
    open($file, "<&$fd")
        or die("Can't dup DB file descriptor: $!\n");
    my @stat = stat($file)
        or die("Can't stat DB file descriptor: $!\n");
    close($file);
    
    return $stat[9]; # mtime
}

1;

__END__

=head1 NAME

IP::Country::DB_File - IP to country translation based on DB_File

=head1 SYNOPSIS

 use IP::Country::DB_File;
 
 my $ipcc = IP::Country::DB_File->new();
 $ipcc->inet_atocc('1.2.3.4');
 $ipcc->inet_atocc('host.example.com');

=head1 DESCRIPTION

IP::Country::DB_File is a light-weight module for fast IP address to country
translation based on L<DB_File>. The country code database is stored in a
Berkeley DB file. You have to build the database using
L<IP::Country::DB_File::Builder> before you can lookup country codes.

This module tries to be API compatible with the other L<IP::Country> modules.
The installation of L<IP::Country> is not required.

=head1 CONSTRUCTOR

=head2 new

 my $ipcc = IP::Country::DB_File->new([ $db_file ]);

Creates a new object and opens the database file I<$db_file>. I<$db_file>
defaults to F<ipcc.db>.

=head1 OBJECT METHODS

=head2 inet_atocc

 $ipcc->inet_atocc($string);

Looks up the country code of host I<$string>. I<$string> can either be an IP
address in dotted quad notation or a hostname.

If successful, returns the country code. In most cases it is an ISO-3166-1
alpha-2 country code, but there are also codes like 'EU' for Europe. See the
documentation of L<IP::Country> for more details.

Returns '**' for private IP addresses.

Returns undef if there's no country code listed for the IP address.

=head2 inet_ntocc

 $ipcc->inet_ntocc($string);

Like I<inet_atocc> but works with a packed IP address.

=head2 db_time

 $ipcc->db_time();

Returns the mtime of the DB file.

=head1 SEE ALSO

L<IP::Country>, L<IP::Country::DB_File::Builder>

=head1 AUTHOR

Nick Wellnhofer <wellnhofer@aevum.de>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Nick Wellnhofer, 2009

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
