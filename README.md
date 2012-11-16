Probes
======

Overview
--------

Probes is a web application based on Mojolicious (Perl Web Framework)
that lets you graph timed data stored inside a PostgreSQL database.

It can generate scripts to collect the activity data on a PostgreSQL
machine (SQL, sysstat), the tarball can then be uploaded to the web
UI, to display the data as graphs.

The purpose of Probes is to have a set of predefined data gathering
commands (e.g. probes) and graphs to quickly show the activity on the
studied server.

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

Then run `sql/probes_init.sql` script on the db to create tables and other
stuff.

Install other prerequisites: Mojolicious is available on CPAN and
sometimes packages, for example the package in Debian is
`libmojolicious-perl`

Copy `probes.conf-dist` to `probes.conf` and edit it.

To quickly run the UI, do not activate `rewrite` in the config (this
is Apache rewrite rules when run as a CGI) and start the morbo
webserver inside the source directory:

	morbo script/probes

It will output what is printed to STDOUT/STDOUT in the code in the
term. The web pages are available on http://localhost:3000/

To run the UI with Apache, here is an example using CGI:

	<VirtualHost *:80>
		ServerAdmin webmaster@example.com
		ServerName probes.example.com
		DocumentRoot /var/www/probes/public/
	
		<Directory /var/www/probes/public/>
			AllowOverride None
			Order allow,deny
			allow from all
			IndexIgnore *
	
			RewriteEngine On
			RewriteBase /
			RewriteRule ^$ probes.cgi [L]
			RewriteCond %{REQUEST_FILENAME} !-f
			RewriteCond %{REQUEST_FILENAME} !-d
			RewriteRule ^(.*)$ probes.cgi/$1 [L]
		</Directory>
	
		ScriptAlias /probes.cgi /var/www/probe/script/probes
		<Directory /var/www/probes/script/>
			AddHandler cgi-script .cgi
			Options +ExecCGI
			AllowOverride None
			Order allow,deny
			allow from all
			SetEnv MOJO_MODE production
			SetEnv MOJO_MAX_MESSAGE_SIZE 4294967296
		</Directory>
	
		ErrorLog ${APACHE_LOG_DIR}/probes_error.log
		# Possible values include: debug, info, notice, warn, error, crit,
		# alert, emerg.
		LogLevel warn
	
		CustomLog ${APACHE_LOG_DIR}/probes_access.log combined
	</VirtualHost>

