requires 'AnyEvent', '0';
requires 'Const::Fast', '0';
requires 'DateTime::HiRes', '0';
requires 'DateTime::Format::CLDR', '0';
requires 'Data::Printer', '1.000004';
requires 'Getopt::Long', '0';
requires 'JSON::XS', '0';
requires 'Moose', '0';
requires 'MooseX::Types::Common', '0';
requires 'MooseX::Types::Moose', '0';
requires 'Params::ValidationCompiler', '>= 0.24';
requires 'Pod::Usage', '0';
requires 'Throwable', '0';

requires 'DR::Tarantool',
    git => 'ssh://git@gitee.220v.ru/220V/tarantool-perl.git',
    ref => '0.60_220v';

on develop => sub {
    requires 'CPAN::Meta::Converter', '== 2.150010';
    requires 'JSON::PP',              '== 2.97001';
    requires 'Minilla',               '== v3.0.17';
};

on 'test' => sub {
    requires 'Test::MockModule', '0';
    requires 'Test::More',       '0.98';
    requires 'Test::Exception';
};
