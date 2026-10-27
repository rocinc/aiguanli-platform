#!/bin/bash
set -euxo pipefail

apt-get update -qq

# postfix.postinst tries to generate a hostname based on /etc/resolv.conf, which
# gets copied in to the docker environment from the host system. On systems
# that are not on a network with a domain, this will result in a failed install.
#
# See https://salsa.debian.org/postfix-team/postfix-dev/-/blob/debian/buster-updates/debian/postfix.postinst#L40
if [ -f /run/.containerenv -o -f /.dockerenv ]; then
	mv /bin/hostname /bin/x-hostname
	echo openproject.local > /etc/hostname
	apt-get install -y postfix
	mv /bin/x-hostname /bin/hostname
fi

# embed all-in-one additional software
apt-get install -y  \
	memcached \
	postfix \
	apache2 \
	supervisor \
	git subversion \
	wget

# Install postgres server versions
for version in $PGVERSION_CHOICES ; do
	apt-get install -yq --no-install-recommends postgresql-$version
done

# remove any existing cluster
service postgresql stop
for version in $PGVERSION_CHOICES ; do
	rm -rf /var/lib/postgresql/{$version}
done

echo "PGBIN: $PGBIN"

# create schema_cache.yml and db/structure.sql
su - postgres -c "$PGBIN/initdb -D /tmp/nulldb -E UTF8"
su - postgres -c "$PGBIN/pg_ctl -D /tmp/nulldb -l /dev/null -l /tmp/nulldb/log -w start"

# give some more time for DB to start
sleep 5

echo "create database structure; create user structure with encrypted password 'p4ssw0rd'; grant all privileges on database structure to structure;" | su - postgres -c psql
# since postgres 15 we need to also explictly grant the user permissions on the public schema
echo "grant all on schema public to structure;" | su - postgres -c 'psql -d structure'

# dump schema
DATABASE_URL=postgres://structure:p4ssw0rd@127.0.0.1/structure RAILS_ENV=production bundle exec rake db:migrate db:schema:dump db:schema:cache:dump

# this line requires superuser rights, which is not always available and doesn't matter anyway
sed -i '/^COMMENT ON EXTENSION/d' db/structure.sql

su - postgres -c "$PGBIN/pg_ctl -D /tmp/nulldb stop"
rm -rf /tmp/nulldb

a2enmod proxy proxy_http
rm -f /etc/apache2/sites-enabled/000-default.conf

rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
truncate -s 0 /var/log/*log
