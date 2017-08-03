 setenforce 0
iptables -F
yum install openldap openldap-clients nss-pam-ldapd -y

authconfig --enableldap --enableldapauth --ldapserver=servera.pod18.example.com --ldapbasedn="dc=example,dc=org" --enableldaptls --ldaploadcacert=http://servera.pod18.example.com/ca.crt  --update
yum -y install autofs

cat >/etc/auto.master <<EOF
/ldapuser /etc/auto.ldap
EOF
cat >/etc/auto.ldap <<EOF
*       -rw,soft,intr 172.25.1.10:/ldapuser/&
EOF
 service autofs start

yum install vsftpd -y 
systemctl start vsftpd
yum -y install httpd
yum install wget -y

