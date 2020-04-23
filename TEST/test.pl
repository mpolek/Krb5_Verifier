#!/bin/perl -w

# In this example, we request authorization and check the return value. We become
# responsible for all HTML. Note that if you hit the "cancel" button, you'll get the
# "Didn't authorize" message, but a browser reload will not re-request authorization
# after that. If you want to mimic re-asking for authorization, you have to send the
# "Status: 401 Unauthorized" instead of "Status: 200 OK"

use strict;

BEGIN {push @INC, "/home/customer/perl_includes";}
use Krb5_Verifier::krb5_verify_user;

if (Krb5_Verifier::krb5_verify_user::verify_HTTP_AUTHORIZATION) {
	print "Status: 200 OK\n";
	print "\n";
	print "<HEAD><TITLE>SUCCESS</TITLE></HEAD><BODY>";
	print "Found user ", defined($ENV{REMOTE_USER}) ? "$ENV{REMOTE_USER}" : ".", "\n";
	print "</BODY>\n";
} else {
	print "Status: 200 OK\n";
	print "\n";
	print "Didn't authorize\n";
}

exit 0;
