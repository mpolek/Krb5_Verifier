Purpose
=======
Do you need to use a kerberos server to verify the identity of a website user, but you don't have access to the webserver configuration files? Do you need something that will mimic mod_auth_kerb without any privileges?

The scripts in this repository are written to provide that functionality. I'm using a well-known hosting provider for testing. Modify the configuration to your liking to work with your environment.

Installation Instructions for Perl
==================================
Place the perl code and any extra needed libraries in an easily accessible place outside your webroot. I used my home directory ~, which shows up as /home/customer in the scripts. Modify as needed.

krb5.conf file
---------
~/krb5.conf

If your forward and reverse DNS for the server don't match (and they probably don't for your hosting provider), be sure to set rdns = false. Put in your kerberos server IPs, or you can use DNS if it is set up correctly... but I recommend starting with IPs to test because DNS can get squirrely.

example:
[libdefaults]
 default_realm = EXAMPLE.COM
 dns_lookup_realm = false
 dns_lookup_kdc = false
 rdns = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true

[realms]
 EXAMPLE.COM =  = {
  default_domain = EXAMPLE.COM
  kdc = 12.34.56.78:88
  kdc = 12.34.56.89:88
  admin_server = myserver.EXAMPLE.COM
 }

[domain_realm]
 .example.com = EXAMPLE.COM
 example.com = EXAMPLE.COM


keytab file
------
Create a keytab file for the service you wish to use. Transfer it securely from your kerberos server.

~/server.hostingprovider.com_MY.KERBEROS.REALM.keytab

Mine has entries like

HTTP/server.hostingprovider.com_MY.KERBEROS.REALM


Perl code: ~/perl_includes
---------
Copy the Krb5_Verifier/krb5_verify_user.pm from this repository to your perl_includes directory.
~/perl_includes/Krb5_Verifier/krb5_verify_user.pm

Perl libraries: ~/perl5/vendor_perl
--------------
You must copy the files for Authen::Krb5 to your perl5/vendor_perl directory. I have
~/perl5/vendor_perl/Authen/Krb5.pm
~/perl5/vendor_perl/auto/Authen/Krb5/Krb5.so
~/perl5/vendor_perl/auto/Authen/Krb5/autosplit.ix

Your cgi-bin directory
----------------------
You must enable perl in your cgi-bin directory, and you MUST force Apache's HTTP:Authorization response into the HTTP_AUTHENTICATION environment variable. (Modify as needed for a different webserver.)
In your public_html/cgi-bin/.htaccess file:

===
SetHandler cgi-script
Options +ExecCGI

<IfModule mod_rewrite.c>
RewriteEngine on
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization},L]
</IfModule>
===

Testing
=======
Running the test script manually should result in:

===
Status: 401 Unauthorized
WWW-Authenticate: Basic realm="YOUR DEFAULT REALM HERE"

<HEAD><TITLE>PASSWORD REQUIRED</TITLE></HEAD><BODY>PASSWORD REQUIRED</BODY>
===

Accessing the URL https://www.yourdomain.tld/cgi-bin/test.pl should trigger a request for authentication from the browser. 
