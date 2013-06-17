# the defaults are all pretty sane, but check to see what they do first :)
include lsi::msm

# or if you use my puppet-shorewall module...
class { '::lsi::msm':
	shorewall => true,
	zone => 'loc',
	allow => '172.16.1.42',	# a trusted management computer
}

