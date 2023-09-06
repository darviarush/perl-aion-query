on 'develop' => sub {
    requires 'Minilla', 'v3.1.19';
};

on 'test' => sub {
	requires 'Liveman',
		git => 'https://github.com/darviarush/perl-liveman.git',
		ref => 'master';
    requires 'Aion::Carp',
        git => 'https://github.com/darviarush/perl-aion-carp.git',
        ref => 'master';
    requires 'Data::Printer', '1.000004';
};

requires 'common::sense', '3.75';
requires 'config',
    git => 'https://github.com/darviarush/perl-config.git',
    ref => 'master';
