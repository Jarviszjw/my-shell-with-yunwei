cat > ~/mkcert.sh  <<EOF
#!/bin/bash

myhostname="$(hostname)"
ca_name="ca.uplooking.com"
ca_key_pass="uplooking"
ca_dir="/etc/pki/CA"
openssl_conf_file="/etc/pki/tls/openssl.cnf"

hostname | grep -q '^localhost$'
[ $? -eq 0 ] && echo "Don't use localhost , reset your hostname." && exit

init_ca_dir()
{
	mkdir /etc/pki/CA/{certs,crl,newcerts} -p
	chmod 0700 /etc/pki/CA/
	chmod 0700 /etc/pki/CA/{certs,crl,newcerts}
	touch /etc/pki/CA/index.txt
	echo 01 > /etc/pki/CA/serial
}

init_ca_cnf()
{
	sed -i 's%^certificate.*%certificate = $dir/my-ca.crt%' $openssl_conf_file
	sed -i 's%^crl\>.*%crl = $dir/my-ca.crl%' $openssl_conf_file
	sed -i 's%^private_key\>.*%private_key = $dir/private/my-ca.key%' $openssl_conf_file
	sed -i 's%^countryName_default\>.*%countryName_default = CN%' $openssl_conf_file
	sed -i 's%^#stateOrProvinceName_default%stateOrProvinceName_default%' $openssl_conf_file
	sed -i 's%^stateOrProvinceName_default\>.*%stateOrProvinceName_default = shanghai%' $openssl_conf_file
	sed -i 's%^localityName_default\>.*%localityName_default = shanghai%' $openssl_conf_file
	sed -i 's%^0.organizationName_default\>.*%0.organizationName_default = uplooking sh. Company Ltd%' $openssl_conf_file
	sed -i 's%^#organizationalUnitName_default%organizationalUnitName_default%' $openssl_conf_file
	sed -i 's%^organizationalUnitName_default\>.*%organizationalUnitName_default = Certificate  Information technology%' $openssl_conf_file
	grep -q '^commonName_default\>' $openssl_conf_file  && sed -i "s%^commonName_default\>.*%commonName_default = $ca_name%" $openssl_conf_file || sed -i "152acommonName_default = $ca_name" $openssl_conf_file
}

create_ca_keys()
{
	echo "create the keys: my-ca.key,my-ca.crt"
	echo "the keys will save in : /etc/pki/CA/ and /etc/pki/CA/private/"
	cd /etc/pki/CA/
	( umask 077 ; openssl genrsa -out private/my-ca.key  -passout pass:$ca_key_pass -des3 2048 &> /dev/null )
	openssl req -new -x509 -key private/my-ca.key  -days 365 -batch -passin pass:$ca_key_pass > my-ca.crt
	echo "create finished , please check."
	exit 0
}


check_ca_keys()
{
	if [ ! -f /etc/pki/CA/private/my-ca.key -o ! -f /etc/pki/CA/my-ca.crt ]
	then
		echo "you should create ca keys first."
		echo "please run : bash $(basename $0) --create-ca-keys"
		exit 88
	fi
}

init_ldap_cnf()
{
	sed -i "s%^commonName_default\>.*%commonName_default = $myhostname%" $openssl_conf_file
}

create_ldap_key()
{
	echo "create the keys: ldap_server.key,ldap_server.crt"
        echo "the keys will save in : /etc/pki/CA/"
	cd /etc/pki/CA/
	openssl genrsa 1024 > ldap_server.key 2> /dev/null
	openssl  req -new -key ldap_server.key -out ldap_server.csr -batch &> /dev/null
	openssl  ca -config /etc/pki/tls/openssl.cnf  -batch -passin pass:$ca_key_pass -out ldap_server.crt -infiles ldap_server.csr &> /dev/null
	echo "create finished , please check."
	exit 0
}

myhelp()
{
	cat << ENDF
usage: bash $(basename $0) [option]
option:
--help			show help
--create-ca-keys	create keys for CA
--create-ldap-keys	create keys for ldap server(you should create ca keys first)
--del-keys		delete keys for CA & ldap
ENDF

	exit 8
}

del-keys()
{
	find /etc/pki/CA/ -type f -exec rm -f {}  \;
}


case $1 in
	--del-keys)
	del-keys;
	;;
	--create-ca-keys)
	[ ! -f $openssl_conf_file.default ] && /bin/cp $openssl_conf_file $openssl_conf_file.default
	init_ca_dir;
	init_ca_cnf;
	create_ca_keys;
	;;
	--create-ldap-keys)
	check_ca_keys;
	init_ldap_cnf;
	create_ldap_key;
	;;
	*)
	myhelp
	;;
esac
	



EOF

iptables -F

setenforce 0
yum install openldap-clients migrationtools openldap-servers openldap -y

cat >/etc/openldap/slapd.conf <<EOF
include         /etc/openldap/schema/corba.schema
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/duaconf.schema
include         /etc/openldap/schema/dyngroup.schema
include         /etc/openldap/schema/inetorgperson.schema
include         /etc/openldap/schema/java.schema
include         /etc/openldap/schema/misc.schema
include         /etc/openldap/schema/nis.schema
include         /etc/openldap/schema/openldap.schema
include         /etc/openldap/schema/pmi.schema
include         /etc/openldap/schema/ppolicy.schema
include         /etc/openldap/schema/collective.schema
allow bind_v2
pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args
####  Encrypting Connections
TLSCACertificateFile /etc/pki/tls/certs/ca.crt
TLSCertificateFile /etc/pki/tls/certs/slapd.crt
TLSCertificateKeyFile /etc/pki/tls/certs/slapd.key
### Database Config###          
database config
rootdn "cn=admin,cn=config"
rootpw {SSHA}IeopqaxvZY1/I7HavmzRQ8zEp4vwNjmF
access to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
### Enable Monitoring
database monitor
# allow only rootdn to read the monitor
access to * by dn.exact="cn=admin,cn=config" read by * none
EOF


rm -rf /etc/openldap/slapd.d/*
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d
chown -R ldap:ldap /etc/openldap/slapd.d
chmod -R 000 /etc/openldap/slapd.d
chmod -R u+rwX /etc/openldap/slapd.d

chmod +x mkcert.sh
./mkcert.sh --create-ca-keys 
./mkcert.sh --create-ldap-keys

cd /etc/pki/CA/
cp my-ca.crt /etc/pki/tls/certs/ca.crt
cp ldap_server.key /etc/pki/tls/certs/slapd.key
cp ldap_server.crt  /etc/pki/tls/certs/slapd.crt
cd ~

rm -rf /var/lib/ldap/*
chown ldap.ldap /var/lib/ldap
cp -p /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap. /var/lib/ldap/DB_CONFIG
systemctl start  slapd.servic

mkdir ~/ldif

cat > ~/ldif/bdb.ldif <<EOF
dn: olcDatabase=bdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcBdbConfig
olcDatabase: {1}bdb
olcSuffix: dc=example,dc=org
olcDbDirectory: /var/lib/ldap
olcRootDN: cn=Manager,dc=example,dc=org
olcRootPW: redhat
olcLimits: dn.exact="cn=Manager,dc=example,dc=org" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn,displayName pres,eq,approx,sub
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: memberUid eq
olcDbIndex: objectClass eq
olcDbIndex: entryUUID pres,eq
olcDbIndex: entryCSN pres,eq
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.children="ou=admins,dc=example,dc=org" write  by * none
olcAccess: to * by self write by dn.children="ou=admins,dc=example,dc=org" write by * read

 -D  用户名
 -w  密码
[root@servera migrationtools]#  ldapsearch -x -b "cn=config" -D "cn=admin,cn=config" -w redhat -h localhost dn -LLL | grep -v ^$
EOF

ldapadd -x -D "cn=admin,cn=config" -w config -f ~/ldif/bdb.ldif -h localhost
adding new entry "olcDatabase=bdb,cn=config"


cd /usr/share/migrationtools/

sed -r -i '/^\$.*_.*_DOMAIN/s/\".+\"/\"example.org\"/' /usr/share/migrate_common.ph
sed -r -i '/^\$.*_BASE/s\".+\"/\"dc=example,dc=org\"/' /usr/share/migrate_common.ph 
#yhhz

mkdir /ldapuser
groupadd -g 10000 ldapuser1
useradd -u 10000 -g 10000 ldapuser1 -d /ldapuser/ldapuser1
echo uplooking | passwd --stdin ldapuser1

grep ^ldapuser /etc/passwd > /root/passwd.out
 cd /usr/share/migrationtools/
./migrate_base.pl > /root/ldif/base.ldif
./migrate_passwd.pl /root/passwd.out  > /root/ldif/password.ldif
./migrate_group.pl /root/group.out > /root/ldif/group.ldif

#tjtm
ldapadd -x -D "cn=Manager,dc=example,dc=org" -w redhat -h localhost -f ~/ldif/base.ldif 
ldapadd -x -D "cn=Manager,dc=example,dc=org" -w redhat -h localhost -f ~/ldif/group.ldif 
ldapadd -x -D "cn=Manager,dc=example,dc=org" -w redhat -h localhost -f ~/ldif/password.ldif 

#ca.crt
yum -y install httpd
cp /etc/pki/tls/certs/ca.crt /var/www/html/
systemctl start httpd
systemctl enable httpd
yum -y install nfs-utils
cat >vim /etc/exports <<EOF
/ldapuser       172.25.1.0/24(rw,async)
EOF

systemctl restart rpcbind
systemctl restart nfs
