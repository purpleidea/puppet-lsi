# Simple lsi raid card monitoring module by James
# Copyright (C) 2012-2013+ James Shubin
# Written by James Shubin <james@shubin.ca>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# NOTE: the associated rpm's were found at:
# ftp://ftp.supermicro.com/driver/SAS/LSI/2108/MSM/Linux/11.06-00/11.06-00.zip

# TODO: add lsi snmp support
# see: sas_ir_snmp-3.17-1126.i386.rpm and sas_snmp-3.17-1123.i386.rpm

class lsi::msm(				# lsi megaraid storage manager (msm)
	$email = ['root@localhost'],	# who should we email alerts to ?
	$megacli = true,
	$config = true,			# manage the 'current' config ?
	$docs = false,			# add docs to server (because i can!)
	$shorewall = false,
	$zone = 'net',			# TODO: allow for a list of zones
	$allow = 'all'			# TODO: allow for a list of ip's per zone
) {
	$FW = '$FW'			# make using $FW in shorewall easier...

	# needed for the 32-bit programs supplied to run on a 64 bit system
	package {[
		'glibc.i686', 'libstdc++.i686', 'compat-libstdc++-33.i686',
		'libXau.i686', 'libxcb.i686', 'libX11.i686', 'libXext.i686',
		'libXi.i686', 'libXtst.i686']:
		ensure => present,
	}

	# Lib_Utils-1.00-09.noarch.rpm (provided by lsi)
	#package { 'Lib_Utils':
	#	ensure => present,
	#}

	# Lib_Utils2-1.00-01.noarch.rpm (provided by lsi)
	#package { 'Lib_Utils2':
	#	ensure => present,
	#}

	# MegaRAID_Storage_Manager-11.06.00-05.noarch.rpm (provided by lsi)
	# NOTE: this package automatically pulls in Lib_Utils and Lib_Utils2
	package { 'MegaRAID_Storage_Manager':
		ensure => present,
		require => Package[['glibc.i686', 'libstdc++.i686',
		'compat-libstdc++-33.i686', 'libXau.i686', 'libxcb.i686',
		'libX11.i686', 'libXext.i686', 'libXi.i686', 'libXtst.i686']],
	}

	if $megacli {
		# MegaCli-8.02.14-1.i386.rpm (provided by lsi)
		package { 'MegaCli':		# add in case i need to cli it!
			ensure => present,
			require => Package[['glibc.i686', 'libstdc++.i686',
			'compat-libstdc++-33.i686', 'libXau.i686',
			'libxcb.i686', 'libX11.i686', 'libXext.i686',
			'libXi.i686', 'libXtst.i686']],	# not sure if needed!
		}
	}

	# NOTE: sane defaults have been chosen
	# TODO: we could add more variables to some of the values in here...
	file { '/usr/local/MegaRAID Storage Manager/MegaMonitor/config-default.xml':
		content => template('lsi/config-default.xml.erb'),
		owner => root,
		group => root,
		mode => 644,			# u=rw,go=r
		ensure => present,
		require => Package['MegaRAID_Storage_Manager'],
		alias => 'lsi-config-default',
	}

	if $config {
		# manage current config ourselves
		file { '/usr/local/MegaRAID Storage Manager/MegaMonitor/config-current.xml':
			content => template('lsi/config-default.xml.erb'),
			owner => root,
			group => root,
			mode => 644,			# u=rw,go=r
			# TODO: find out which service(s) actually need to be reset
			notify => [
				Service['mrmonitor'],
				Service['vivaldiframeworkd']
			],
			before => [
				Service['mrmonitor'],
				Service['vivaldiframeworkd']
			],
			ensure => present,
			require => Package['MegaRAID_Storage_Manager'],
		}
	} else {
		# copy 'current config' once, and let the gui manage it after
		exec { "/bin/cp -a '/usr/local/MegaRAID Storage Manager/MegaMonitor/config-default.xml' '/usr/local/MegaRAID Storage Manager/MegaMonitor/config-current.xml'":
			logoutput => on_failure,
			refreshonly => true,
			before => [
				Service['mrmonitor'],
				Service['vivaldiframeworkd']
			],
			subscribe => Package['MegaRAID_Storage_Manager'],	# get an initial 'notify'
			require => File['/usr/local/MegaRAID Storage Manager/MegaMonitor/config-default.xml'],
		}
	}

	service { 'mrmonitor':
		enable => true,			# start on boot
		ensure => running,		# ensure it stays running
		hasstatus => true,		# use status command to monitor
		hasrestart => true,		# use restart, not start; stop
		require => File['lsi-config-default'],
	}

	service { 'vivaldiframeworkd':
		enable => true,			# start on boot
		ensure => running,		# ensure it stays running
		hasstatus => true,		# use status command to monitor
		hasrestart => true,		# use restart, not start; stop
		require => File['lsi-config-default'],
	}

	if $docs {
		# puppet can be cool and make hard to find documentation, easy!
		file { '/root/LSI_SAS_EmbMRAID_SWUG.pdf':
			owner => root,
			group => root,
			mode => 644,	# u=rw,go=r
			source => 'puppet:///modules/lsi/LSI_SAS_EmbMRAID_SWUG.pdf',
		}
	}

	# FIXME: it seems other msm's try to communicate on the network at port tcp:49258
	# it's not clear that this should be opened or not.. TBD. Maybe it should be blocked silently from leaving?
	if $shorewall {
		if $allow == 'all' or "${allow}" == '' {
			$net = "${zone}"
		} else {
			$net = is_array($allow) ? {
				true => sprintf("${zone}:%s", join($allow, ',')),
				default => "${zone}:${allow}",
			}
		}
		############################################################################
		# ACTION      SOURCE DEST                PROTO DEST  SOURCE  ORIGINAL
		#	                                       PORT  PORT(S) DEST
		shorewall::rule { 'lsi': rule => "
		ACCEPT        ${net}    $FW    tcp 3071
		ACCEPT        ${net}    $FW    udp 3071
		ACCEPT        ${net}    $FW    udp 5571
		ACCEPT        ${net}    $FW    tcp 65000	# this was found by inspection. it seems it's needed for configuring alerts remotely.
		", comment => 'Allow access to lsi2108 monitoring daemons'}
	}
}

