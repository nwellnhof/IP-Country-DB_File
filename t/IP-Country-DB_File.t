use Test::More tests => 51;
BEGIN { use_ok('IP::Country::DB_File') };
BEGIN { use_ok('IP::Country::DB_File::Builder') };

my $filename = 't/ipcc.db';
unlink($filename);

my $builder = IP::Country::DB_File::Builder->new($filename);
ok(defined($builder), 'new');

local *FILE;
ok(open(FILE, '<', 't/delegated-test'), 'open source file');
ok($builder->_import_file(*FILE) == 81, 'import file');
$builder->_store_private_networks();
$builder->_sync();
close(FILE);

ok(-e $filename, 'create db');

my $ipcc = IP::Country::DB_File->new($filename);

ok(abs($ipcc->db_time() - time()) < 24 * 3600, 'db_time');

my @tests = qw(
    0.0.0.0         ?
    0.0.0.1         ?
    0.0.1.0         ?
    0.1.0.0         ?
    1.2.3.4         ?
    9.255.255.255   ?
    10.0.0.0        **
    10.255.255.255  **
    11.0.0.0        ?
    24.131.255.255  ?
    24.132.0.0      NL
    24.132.127.255  NL
    24.132.128.0    NL
    24.132.255.255  NL
    24.133.0.0      ?
    24.255.255.255  ?
    25.0.0.0        GB
    25.50.100.200   GB
    25.255.255.255  GB
    26.0.0.0        ?
    33.177.178.99   ?
    61.1.255.255    ?
    62.12.95.255    CY
    62.12.96.0      ?
    62.12.127.255   ?
    62.12.128.0     CH
    172.15.255.255  ?
    172.16.0.0      **
    172.31.255.255  **
    172.32.0.0      ?
    192.167.255.255 ?
    192.168.0.0     **
    192.168.255.255 **
    192.169.0.0     ?
    217.198.128.241 UA
    217.255.255.255 DE
    218.0.0.0       ?
    218.0.0.1       ?
    218.0.0.111     ?
    218.0.111.111   ?
    218.111.111.111 ?
    224.111.111.111 ?
    254.111.111.111 ?
    255.255.255.255 ?
);

for(my $i=0; $i<@tests; $i+=2) {
    my ($ip, $test_cc) = ($tests[$i], $tests[$i+1]);
    #print STDERR ("\n*** $ip $cc ", $ipcc->inet_atocc($ip));
    my $cc = $ipcc->inet_atocc($ip);
    $cc = '?' unless defined($cc);
    ok($cc eq $test_cc, "lookup $ip, got $cc, expected $test_cc");
}

unlink($filename);
