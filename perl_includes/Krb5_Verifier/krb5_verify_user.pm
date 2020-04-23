#!/bin/perl -w

use strict;
package Krb5_Verifier::krb5_verify_user;

# krb5_verfiy_user
#
# This program attempts to validate a user/password transferred via the BasicAuth
# mechanism. Note that BasicAuth is NOT secure. Thus this script should ONLY be called
# via HTTPS.
#
# The program assumes that the user/password are passed in an environment variable set up by
# the following RewriteRule:
#
# RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization},L]
#
# The HTTP_AUTHORIZATION environment variable will contain the BasicAuth information as
# "Basic <encoded string>"
#
# You must properly configure your krb5.conf file, and the client and server need to know who each
# other are using DNS and reverse DNS. 
#

my $DEBUG = 0;

## Initialize

my $realm = undef;    # Set here if you don't want the default Kerberos realm.
my $server = `/bin/hostname`; # Be sure rdns is off in krb5.conf if your hostname isn't in reverse DNS
chomp $server;
my $service = "HTTP";
my $home_directory;
BEGIN{ $home_directory = "/home/customer"; }

use lib "${home_directory}/perl5/vendor_perl";
use Authen::Krb5;

# Defaults values. If we can determine local website path, these get updated.
my $BasicAuthRealm = "YOUR DEFAULT REALM HERE";
my $logfile = "${home_directory}/krb5_verify_user_log.txt";

# Determine current website from ENV HTTP_HOST
if (defined($ENV{HTTP_HOST}) && "$ENV{HTTP_HOST}" ne "") {
	$BasicAuthRealm = "$ENV{HTTP_HOST}";
	# Our ISP structures websites at ~/www/<sitename>/public_html
	# Put the debug log above the public_html directory
	if ( -w "${home_directory}/www/$BasicAuthRealm/") {
		$logfile = "${home_directory}/www/$BasicAuthRealm/krb5_verify_user_log.txt";
	}
}

# Init logfile if we are DEBUGging
if ($DEBUG) {
	open MYLOG, ">$logfile";
	MYLOG->autoflush(1);
	print MYLOG scalar localtime(), "   DEBUG=$DEBUG\n";
}

# Init Kerberos
$ENV{"KRB5_CONFIG"} = "${home_directory}/krb5.conf";
my $context = undef;


## Subroutine to re-display Auth request

sub noauth {
	my $WA = shift;
	my $msg = shift;
	print MYLOG "Caller context: ", defined($WA) ? "$WA" : "VOID", "\n" if $DEBUG > 2;
	print MYLOG "NoAuth error: $msg\n" if $DEBUG;
	print MYLOG "Authen Error: ", Authen::Krb5::error(), "\n" if $DEBUG > 1;
       	# If caller requested a return value. Send back FALSE/FAIL. Caller is responsible for HTTP response.
	return 0 if defined($WA);

	# If no return value requested (void context), show default HTTP response.
	print "Status: 401 Unauthorized", "\n";
	print "WWW-Authenticate: Basic realm=\"$BasicAuthRealm\"","\n";
	print "\n";
	print "<HEAD><TITLE>NO ACCESS</TITLE></HEAD><BODY>NO ACCESS</BODY>\n";
	exit 1;
}

# Process HTTP_AUTHORIZATION from the environment
sub verify_HTTP_AUTHORIZATION {

	# Save caller context. Could be VOID, 0, or 1. If it's VOID, repeat auth request indefinitely.
	my $WA = wantarray();

	# Init Kerberos context
	$context = Authen::Krb5::init_context() || return noauth($WA,"init_context");

	# Configuration
	$realm = Authen::Krb5::get_default_realm() if !defined($realm);
	my $server_principal_name = "$service/$server\@$realm";
	my $server_keytab_location = "${home_directory}/${server}_${realm}.keytab";

	# Check for authorization string from browser.
	my $REMOTE_USER = "";
	my $REMOTE_PASSWORD = "";
	my $HTTP_AUTHORIZATION = $ENV{HTTP_AUTHORIZATION};

	if ( !defined($HTTP_AUTHORIZATION)) {
		print "Status: 401 Unauthorized", "\n";
		print "WWW-Authenticate: Basic realm=\"$BasicAuthRealm\"","\n";
		print "\n";
		print "<HEAD><TITLE>PASSWORD REQUIRED</TITLE></HEAD><BODY>PASSWORD REQUIRED</BODY>\n";
		exit 0;
	} else {
		use MIME::Base64 qw( decode_base64 );
		my $authstring = $ENV{HTTP_AUTHORIZATION};
		$authstring =~ /^Basic\s+([A-Za-z0-9=]+)$/ || return noauth($WA,"decode 'authstring'");
		my $decoded = decode_base64($1);
		$decoded =~ /^([A-Za-z0-9]+):(.+)$/ || return noauth($WA,"parse 'decoded' - empty password?");
		$REMOTE_USER = "$1";
		$REMOTE_PASSWORD = "$2";
	}

	###### Validate user/pass against Kerberos database.

	# Obtain client credentials from kerberos server
	defined($REMOTE_USER) && $REMOTE_USER ne "" || return noauth($WA,"no remote user");
	defined($REMOTE_PASSWORD) && $REMOTE_PASSWORD ne "" || return noauth($WA,"no remote password");
	my $client_principal = Authen::Krb5::parse_name($REMOTE_USER) || return noauth($WA,"parse_name cp");
	my $client_creds = Authen::Krb5::get_init_creds_password($client_principal, $REMOTE_PASSWORD) || return noauth($WA,"get_init_creds_password");

	# Store client credentials in credential cache
	my $cc = Authen::Krb5::cc_resolve("MEMORY:");
	$cc->initialize($client_principal) || return noauth($WA,"init cc");
	$cc->store_cred($client_creds) || return noauth($WA,"store_cred");

	# Create REQ for validation using client credentials
	my $auth_context = Authen::Krb5::AuthContext->new() || return noauth($WA,"new auth_context");
	my $req = Authen::Krb5::mk_req($auth_context,AP_OPTS_MUTUAL_REQUIRED,$service,$server,"",$cc) || return noauth($WA,"mk_req '$server'"); # 5th param is arbitrary string to be checksummed or empty
	$cc->destroy() || return noauth($WA,'cc destroy'); # We're done with the credential cache. Free it up.

	# Use keytab for validating server using REQ
	my $kt = Authen::Krb5::kt_resolve($server_keytab_location) || return noauth($WA,"kt_resolve");
	my $server_principal = Authen::Krb5::parse_name("$server_principal_name") || return noauth($WA,"parse_name sp");

	$auth_context = undef; # Need a fresh auth_context. Throw the old one away.
	$auth_context = Authen::Krb5::AuthContext->new() || return noauth($WA,"new auth_context 2");

	# Obtain ticket from REQ
	my $ticket = Authen::Krb5::rd_req($auth_context,$req,$server_principal,$kt) || return noauth($WA,"rd_req");
	my ($tservice,$tserver) = $ticket->server->data;

	print MYLOG "ticket service:\t$tservice\n",
		"ticket server:\t$tserver\n",
		"ticket realm:\t", $ticket->server->realm, "\n",
		"ticket client:\t", $ticket->enc_part2->client->data, "\n"
		if $DEBUG > 1;

	# Verify ticket components
	$tservice				eq "$service"			|| return noauth($WA,"bad ticket service data");
	$tserver				eq "$server"			|| return noauth($WA,"bad ticket server data");
	$ticket->server->realm			eq "$realm"			|| return noauth($WA,"bad ticket server realm");
	$ticket->enc_part2->client->data	eq "$REMOTE_USER"		|| return noauth($WA,"bad ticket client data");

	print MYLOG Authen::Krb5::error(), "\n" if $DEBUG;

	Authen::Krb5::free_context();

	print MYLOG "Verified client '", $ticket->enc_part2->client->data, "'\n" if $DEBUG;

	# Place remote user in ENV for script to use
	$ENV{REMOTE_USER} = "$REMOTE_USER";

	return 1; # Success!
}

1;
