Probe
=====

Overview
--------

Probe is a web application based on Mojolicious (Perl Web Framework)
that lets you graph timed data stored inside a PostgreSQL database.

It can generate scripts to collect the activity data on a PostgreSQL
machine (SQL, sysstat), the tarball can then be uploaded to the web
UI, to display the data as graphs.

The purpose of Probe is have a set of predefined probes (data
gathering commands) and graphs to quickly show the activity on the
probed server.

Prerequisites
-------------

The versions showed have been tested, it may work with older versions

* Perl 5.10
* Mojolicious 2.98
* PostgreSQL 9.0
* A CGI/Perl webserver

Install
-------

A PostgreSQL database with a non superuser with the ability to create
new schemas is required. So, first create a database and a user, set
things up to allow the connection from the webserver with this user to
the db.

Then run `sql/db.sql` script on the db to create tables and other
stuff.

Install other prerequisites: Mojolicious is available on CPAN and
sometimes packages, for example the package in Debain is
`libmojolicious-perl`

Copy `probe.conf-dist` to `probe.conf` and edit it.

To quickly run the UI, do not activate `rewrite` in the config (this
is Apache rewrite rules when run as a CGI) and start the morbo
webserver inside the source directory:

	morbo script/probe

It will output what is printed to STDOUT/STDOUT in the code in the
term. The web pages are available on http://localhost:3000/

To run the UI with Apache, here is an example using CGI:

	<VirtualHost *:80>
		ServerAdmin webmaster@example.com
		ServerName probe.example.com
		DocumentRoot /var/www/probe/public/
	
		<Directory /var/www/probe/public/>
			AllowOverride None
			Order allow,deny
			allow from all
			IndexIgnore *
	
			RewriteEngine On
			RewriteBase /
			RewriteRule ^$ probe.cgi [L]
			RewriteCond %{REQUEST_FILENAME} !-f
			RewriteCond %{REQUEST_FILENAME} !-d
			RewriteRule ^(.*)$ probe.cgi/$1 [L]
		</Directory>
	
		ScriptAlias /probe.cgi /var/www/probe/script/probe
		<Directory /var/www/probe/script/>
			AddHandler cgi-script .cgi
			Options +ExecCGI
			AllowOverride None
			Order allow,deny
			allow from all
			SetEnv MOJO_MODE production
			SetEnv MOJO_MAX_MESSAGE_SIZE 4294967296
		</Directory>
	
		ErrorLog ${APACHE_LOG_DIR}/probe_error.log
		# Possible values include: debug, info, notice, warn, error, crit,
		# alert, emerg.
		LogLevel warn
	
		CustomLog ${APACHE_LOG_DIR}/probe_access.log combined
	</VirtualHost>

