#!/bin/sh -ex

##
## Tunnel all TCP data and DNS requests from a network interface (e.g. TUN/TAP
## from a virtual machine) over TOR. Includes a DHCP server.
##
## Needs dhcpd, sipcalc, sudo, iptables, tor.
##
##
## Configuration:

TUNIF=vboxnet0
DNSPORT=9053
TCPPORT=9040

## End of configuration.
##


TUNIP=$(sipcalc $TUNIF | awk -F'- ' '/Host address\s*-/ {print $2}')
TUNNET=$(sipcalc $TUNIF | awk -F'- ' '/Network address\s*-/ {print $2}')
TUNMASK=$(sipcalc $TUNIF | awk -F'- ' '/Network mask\s*-/ {print $2}')
TUNRANGE=$(sipcalc $TUNIF | awk -F'[ \t]- ' '/Usable range\s*-/ {print $2 " " $3}')

# ask for pw early and do something with iptables to fail early (no cleanup necessary)
sudo iptables -t nat -L

TORCONFIG=$(mktemp)
TORDATA=$(mktemp -d)

cat << EOF > $TORCONFIG
# Temp TOR config
User nobody
DataDirectory ${TORDATA}
TransPort ${TUNIP}:${TCPPORT}
DNSPort ${TUNIP}:${DNSPORT}
SocksPort 0

EOF

DHCPCONFIG=$(mktemp)
DHCPLEASE=$(mktemp)
DHCPPID=$(mktemp)
cat << EOF > $DHCPCONFIG
subnet $TUNNET netmask $TUNMASK {
  range ${TUNRANGE};
  option routers ${TUNIP};
  option domain-name-servers ${TUNIP};
}
EOF

# stay root so we can clean up later
# don't exit on error
sudo /bin/sh -x << EOF

chown nobody:nobody $TORCONFIG $TORDATA

dhcpd -cf $DHCPCONFIG -lf $DHCPLEASE -pf $DHCPPID $TUNIF

iptables -t nat -A PREROUTING -i $TUNIF -p udp --dport 53 -j REDIRECT --to-ports $DNSPORT
iptables -t nat -A PREROUTING -i $TUNIF -p tcp --syn -j REDIRECT --to-ports $TCPPORT

tor -f $TORCONFIG

# TOR started in foreground

# on exit: clean up
# backslash because this must not be evaluated early (in here-doc)
kill \$(cat $DHCPPID)
iptables -t nat -D PREROUTING -i $TUNIF -p udp --dport 53 -j REDIRECT --to-ports $DNSPORT
iptables -t nat -D PREROUTING -i $TUNIF -p tcp --syn -j REDIRECT --to-ports $TCPPORT

rm -r $TORDATA $TORCONFIG $DHCPCONFIG $DHCPLEASE $DHCPPID

EOF
