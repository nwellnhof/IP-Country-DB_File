package IP::Country::DB_File::Builder;

use strict;
use vars qw($VERSION @ISA @EXPORT @rirs);

use DB_File ();
use Fcntl ();

BEGIN {
    $VERSION = '2.00';
    
    require Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(fetch_files remove_files command);

    # Regional Internet Registries
    @rirs = (
        { name=>'arin',    server=>'ftp.arin.net'    },
        { name=>'ripencc', server=>'ftp.ripe.net'    },
        { name=>'afrinic', server=>'ftp.afrinic.net' },
        { name=>'apnic',   server=>'ftp.apnic.net'   },
        { name=>'lacnic',  server=>'ftp.lacnic.net'  },
    );
}

sub new {
    my ($class, $db_file) = @_;
    $db_file = 'ipcc.db' unless defined($db_file);

    my $this = {
        range_count   => 0,
        address_count => 0,
    };

    my %db;
    my $flags = Fcntl::O_RDWR|Fcntl::O_CREAT|Fcntl::O_TRUNC;
    $this->{db} = tie(%db, 'DB_File', $db_file, $flags, 0666,
                      $DB_File::DB_BTREE)
        or die("Can't open database $db_file: $!");
    
    return bless($this, $class);
}

sub _store_ip_range {
    my ($this, $start, $end, $cc) = @_;

    my $key  = pack('N', $end - 1);
    my $data = pack('Na2', $start, $cc);
    $this->{db}->put($key, $data) >= 0 or die("dbput: $!");

    ++$this->{range_count};
    $this->{address_count} += $end - $start;
}

sub _store_private_networks {
    my $this = shift;

    # 10.0.0.0
    $this->_store_ip_range(0x0a000000, 0x0b000000, '**');
    # 172.16.0.0
    $this->_store_ip_range(0xac100000, 0xac200000, '**');
    # 192.168.0.0
    $this->_store_ip_range(0xc0a80000, 0xc0a90000, '**');
}

sub _import_file {
    my ($this, $file) = @_;
    
    my $count = 0;
    my $prev_start = 0;
    my $prev_end   = 0;
    my $prev_cc    = '';
    my $seen_header;

    while(my $line = readline($file)) {
        next if $line =~ /^#/ or $line !~ /\S/;

        unless($seen_header) {
            $seen_header = 1;
            next;
        }

        my ($registry, $cc, $type, $start, $value, $date, $status) =
            split(/\|/, $line);

        next unless $type eq 'ipv4' && $start ne '*';

        # TODO (paranoid): validate $cc, $start and $value

        my $ip_num = unpack('N', pack('C4', split(/\./, $start)));

        die("IP addresses not sorted (line $.)")
            if $ip_num < $prev_end;

        if($ip_num == $prev_end && $prev_cc eq $cc) {
            # optimization: concat ranges of same country
            $prev_end += $value;
        }
        else {
            $this->_store_ip_range($prev_start, $prev_end, $prev_cc)
                if $prev_cc;

            $prev_start = $ip_num;
            $prev_end   = $ip_num + $value;
            $prev_cc    = $cc;
            ++$count;
        }
    }

    $this->_store_ip_range($prev_start, $prev_end, $prev_cc) if $prev_cc;
    
    return $count;
}

sub _sync {
    my $this = shift;

    $this->{db}->sync() >= 0 or die("dbsync: $!");
}

sub build {
    my ($this, $dir) = @_;
    $dir = '.' unless defined($dir);

    for my $rir (@rirs) {
        my $file;
        my $filename = "$dir/delegated-$rir->{name}";
        CORE::open($file, '<', $filename)
            or die("Can't open $filename: $!, " .
                   "maybe you have to fetch files first");

        eval {
            $this->_import_file($file);
        };

        my $error = $@;
        close($file);
        die($error) if $error;
    }

    $this->_store_private_networks();

    $this->_sync();
}

# functions

sub fetch_files {
    my ($dir, $verbose) = @_;
    $dir = '.' unless defined($dir);

    require Net::FTP;

    for my $rir (@rirs) {
        my $server = $rir->{server};
        my $name = $rir->{name};
        my $ftp_dir = "/pub/stats/$name";
        my $filename = "delegated-$name-latest";

        print("fetching ftp://$server$ftp_dir/$filename\n") if $verbose;

        my $ftp = Net::FTP->new($server)
            or die("Can't connect to FTP server $server: $@");
        $ftp->login('anonymous', '-anonymous@')
            or die("Can't login to FTP server $server: " . $ftp->message());
        $ftp->cwd($ftp_dir)
            or die("Can't find directory $ftp_dir on FTP server $server: " .
                   $ftp->message());
        $ftp->get($filename, "$dir/delegated-$name")
            or die("Get $filename from FTP server $server failed: " .
                   $ftp->message());
        $ftp->quit();
    }
}

sub remove_files {
    my $dir = shift;
    $dir = '.' unless defined($dir);

    for my $rir (@rirs) {
        my $name = $rir->{name};
        unlink("$dir/delegated-$name");
    }
}

sub command {
    require Getopt::Std;
    
    my %opts;
    Getopt::Std::getopts('vfbrd:', \%opts) or exit(1);
    
    die("extraneous arguments\n") if @ARGV > 1;
    
    my $dir = $opts{d};
    
    eval {
        fetch_files($dir, $opts{v}) if $opts{f};
    
        if($opts{b}) {
            print("building database...\n") if $opts{v};

            my $builder = __PACKAGE__->new($ARGV[0]);
            $builder->build($dir);

            # we define usable IPv4 address space as 1.0.0.0 - 223.255.255.255
            # excluding 127.0.0.0/8
             
            print(
                "total merged IP ranges: $builder->{range_count}\n",
                "total IP addresses: $builder->{address_count}\n",
                sprintf('%.2f', 100 * $builder->{address_count} / 0xde000000),
                "% of usable IPv4 address space\n",
            ) if $opts{v};
        }
    };

    if($@) {
        print STDERR ($@);
    }

    if($opts{r}) {
        print("removing statistics files\n") if $opts{v};
        remove_files($dir);
    }
}

1;

__END__

=head1 NAME

IP::Country::DB_File::Builder - Build an IP address to country code database

=head1 SYNOPSIS

 perl -MIP::Country::DB_File::Builder -e command -- -fbr
  
 use IP::Country::DB_File::Builder;
 
 fetch_files();
 my $builder = IP::Country::DB_File::Builder->new('ipcc.db');
 $builder->build();
 remove_files();

=head1 DESCRIPTION

This module builds the database used to lookup country codes from IP addresses
with L<IP::Country::DB_File>.

The database is built from the publically available statistics files of the
Regional Internet Registries. Currently, the files are downloaded from the
following hard-coded locations:

 ftp://ftp.arin.net/pub/stats/arin/delegated-arin-latest
 ftp://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-latest
 ftp://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-latest
 ftp://ftp.apnic.net/pub/stats/apnic/delegated-apnic-latest
 ftp://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-latest

You can build the database directly in Perl, or by calling the I<command>
subroutine from the command line. Since the country code data changes
constantly, you should consider updating the database from time to time.
You can also use a database built on a different machine as long as the
I<libdb> versions are compatible.

=head1 CONSTRUCTOR

=head2 new

 my $builder = IP::Country::DB_File::Builder->new([ $db_file ]);

Creates a new builder object and the database file I<$db_file>. I<$db_file>
defaults to F<ipcc.db>. The database file is truncated if it already exists.

=head1 OBJECT METHODS

=head2 build

 $builder->build([ $dir ]);

Builds a database from the statistics files in directory I<$dir>. I<$dir>
defaults to the current directory.

=head1 FUNCTIONS

The following functions are exported by default.

=head2 fetch_files

 fetch_files([ $dir ]);

Fetches the statistics files from the FTP servers of the RIRs and stores them
in I<$dir>. I<$dir> defaults to the current directory. This function requires
L<Net::FTP>.

This function only fetches files and doesn't build the database yet.

=head2 remove_files

 remove_files([ $dir ]);

Deletes the previously fetched statistics files in I<$dir>. I<$dir> defaults
to the current directory.

=head2 command

You can call this subroutine from the command line to update the country code
database like this:

 perl -MIP::Country::DB_File::Builder -e command -- [options] [dbfile]

I<dbfile> is the database file and defaults to F<ipcc.db>. Options include

=head3 -f

fetch files

=head3 -b

build database

=head3 -v

verbose output

=head3 -r

remove files

=head3 -d [dir]

directory for the statistics files

You should provide at least one of the I<-f>, I<-b> or I<-r> options, otherwise
this routine does nothing.

=head1 AUTHOR

Nick Wellnhofer <wellnhofer@aevum.de>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Nick Wellnhofer, 2009

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
