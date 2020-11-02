#!/usr/bin/env perl
# List devices connected to your Altibox router
# Author: Terje Sannum <terje@offpiste.org>
# URL: https://github.com/terjesannum/altibox

use strict;
use Getopt::Long;
use HTTP::Cookies;
use InfluxDB::LineProtocol qw(data2line);
use JSON;
use LWP::UserAgent;
use Text::Table;
use Time::HiRes qw(gettimeofday);
use URI;

$|=1;

my($command, $user, $password, $verbose, $format, $output, $loop);
my $ok = GetOptions("command=s" => \$command,
                    "user=s"      => \$user,
                    "password=s"  => \$password,
                    "output=s"    => \$output,
                    "format=s"    => \$format,
                    "loop=i"      => \$loop,
                    "verbose"     => \$verbose
    );

$command = $ENV{'ALTIBOX_COMMAND'} unless(defined($command));
$user = $ENV{'ALTIBOX_USER'} unless(defined($user));
$password = $ENV{'ALTIBOX_PASSWORD'} unless(defined($password));
$format = ($ENV{'ALTIBOX_FORMAT'} || 'table') unless(defined($format));
$output = ($ENV{'ALTIBOX_OUTPUT'} || '-') unless(defined($output));
$loop = $ENV{'ALTIBOX_LOOP'} unless(defined($loop));
$verbose = $ENV{'ALTIBOX_VERBOSE'} unless(defined($verbose));

$ok = ($ok && $command =~ /^(devices)$/ && $format =~ /^(raw|influxdb|table)$/ && $user ne "" &&  $password ne "");
die "Usage: $0 --command devices --user <user> --password <password> [--verbose] [--format <raw|influxdb|table>] [--output <file>] [--loop <seconds>]\n" unless($ok);

while(1) {

    my $cookies = HTTP::Cookies->new();
    my $ua = LWP::UserAgent->new;
    $ua->ssl_opts(SSL_cipher_list => 'DEFAULT:!DH');
    $ua->cookie_jar($cookies);
    push @{$ua->requests_redirectable}, 'POST';

    verbose("========== Get base data\n");
    my $res = $ua->get('https://www.altibox.no/altibox/js/altibox.min.js');
    die $res->status_line unless($res->is_success);
    my($client_id, $scope, $client_secret) = $res->content =~ m|{baseUrl:\"https://idconnect.cloud\",client_id:\"(.+?)\",scope:\"(.+?)\",client_secret:\"(.+?)\"|;
    die "client_id not found\n" unless $client_id;
    die "scope not found\n" unless $scope;
    die "client_secret not found\n" unless $client_secret;
    verbose("client_id: %s\nscope: %s\nclient_secret: %s\n", $client_id, $scope, $client_secret);

    verbose("========== Get entity id\n");
    my %query_params = (client_id     => $client_id,
                        locale        => 'no',
                        redirect_uri  => 'https://www.altibox.no/auth/callback/',
                        response_type => 'code',
                        scope         => $scope,
                        state         => '/mine-sider/',
                        template      => 'altibox'
        );
    my $uri = URI->new("https://idconnect.cloud/uas/oauth2/authorization");
    $uri->query_form(%query_params);
    $res = $ua->get($uri);
    die $res->status_line unless($res->is_success);
    my($redirres) = $res->previous;
    die "Unexpected response\n" unless($redirres);
    my($entity_id) = $redirres->header("Location") =~ /[?&]_id=([^&]+)/;
    die sprintf("Couldn't find id in url: %s\n", $redirres->header("Location")) unless($entity_id);
    verbose("entity_id: %s\n", $entity_id);

    verbose("========== Logging in\n");
    %query_params = ( entityID => $entity_id,
                      locale   => 'no'
        );
    my %query_data = ( username => $user,
                       password => $password,
                       method   => 'password.2'
        );
    $uri = URI->new(sprintf("https://idconnect.cloud/uas/authn/%s/submit", $entity_id));
    $uri->query_form(%query_params);
    $res = $ua->post($uri, \%query_data);
    die $res->status_line unless($res->is_success);
    die "Login failed" unless($res->content =~ /Du er logget inn/);
    my($code) = $res->content =~ /name="code" value="(.*?)"/;
    die "code not found\n" unless $code;
    verbose("code: %s\n", $code);

    verbose("========== Get token\n");
    %query_data = ( client_id => $client_id,
                    client_secret => $client_secret,
                    code => $code,
                    grant_type => 'authorization_code',
                    redirect_uri => 'https://www.altibox.no/auth/callback/'
        );
    $uri = URI->new('https://idconnect.cloud/uas/oauth2/token');
    $res = $ua->post($uri, \%query_data);
    die $res->status_line unless($res->is_success);
    my $json = decode_json($res->content);
    my $token = $json->{'access_token'};
    die "No access token\n" unless($token);
    verbose("token: %s\n", $token);
    $cookies->set_cookie(0, 'sso_access_token', $token, '/', 'www.altibox.no');

    verbose("========== Get api session ticket\n");
    $uri = URI->new('https://www.altibox.no/api/authentication/token');
    $res = $ua->post($uri,
                     Authorization => sprintf("Bearer %s", $token));
    die $res->status_line unless($res->is_success);
    $json = decode_json($res->content);
    my $ticket = $json->{'data'}->{'sessionTicket'}->{'identifier'};
    die "No session ticket\n" unless($ticket);
    verbose("ticket: %s\n", $ticket);
    $cookies->set_cookie(0, 'sessionTicketApi', $ticket, '/', 'www.altibox.no');

    verbose("========== Get site_id\n");
    $uri = URI->new('https://www.altibox.no/api/customer/servicelocations');
    $res = $ua->get($uri,
                    "SessionTicket" => $ticket);
    die $res->status_line unless($res->is_success);
    $json = decode_json($res->content);
    my $site_id = $json->{'value'}->[0]->{'siteId'};
    die "Couldn't find site id\n" unless($site_id =~ /^\d+$/);
    verbose("site_id: %s\n", $site_id);

    while(1) {
        verbose("========== Query api\n");
        %query_params = ( activeOnly => 'false',
                          siteid => $site_id,
                          _ => sprintf("%s000", time())
            );
        $uri = URI->new('https://www.altibox.no/api/wifi/getlandevices');
        $uri->query_form(%query_params);
        $res = $ua->get($uri);
        unless($res->is_success) {
            printf STDERR ("Query API failed: %s\n", $res->status_line);
            last;
        }
        $json = decode_json($res->content);
        if($json->{'status'} eq 'notAuthenticated') {
            print STDERR "Query API failed: Not authenticated\n";
            last;
        }

        my($f) = \*STDOUT;
        if($output ne '-') {
            open($f, ">$output") || die "Can't open $output: $!\n";
        }
        if($format eq 'raw') {
            print $f $res->content;
        } elsif($format eq 'influxdb') {
            my $timestamp = sprintf("%s%06d000", gettimeofday());
            map { printf $f ("%s\n",
                         data2line('altibox.device',
                                   {ip => $_->{'ipAddress'}, connection => $_->{'connectionType'}, rssi => $_->{'wifiRssi'}, online => $_->{'connectionType'} eq 'DISCONNECTED' ? 0 : 1},
                                   {name => $_->{'hostname'}, mac => $_->{'macAddress'}},
                                   $timestamp)
                      ) } @{$json->{'networkClients'}};
        } else {
            my $table = Text::Table->new('Name','MAC','IP','Connection','RSSI');
            $table->load(map { [ $_->{'hostname'}, $_->{'macAddress'}, $_->{'ipAddress'}, $_->{'connectionType'}, $_->{'wifiRssi'} ] } @{$json->{'networkClients'}});
            print $f $table;
        }
        verbose("Output written to %s\n", $output) unless($output eq '-');
        close($f) if($output ne '-');

        (defined($loop) && $loop > 0) ? sleep($loop) : last;
    } # Query api loop end

    (defined($loop) && $loop > 0) ? sleep($loop) : last;
} # Main loop end

sub verbose {
    printf STDERR @_ if($verbose);
}
