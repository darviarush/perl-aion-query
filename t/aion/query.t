use common::sense; use open qw/:std :utf8/; use Test::More 0.98; sub _mkpath_ { my ($p) = @_; length($`) && !-e $`? mkdir($`, 0755) || die "mkdir $`: $!": () while $p =~ m!/!g; $p } BEGIN { use Scalar::Util qw//; use Carp qw//; $SIG{__DIE__} = sub { my ($s) = @_; if(ref $s) { $s->{STACKTRACE} = Carp::longmess "?" if "HASH" eq Scalar::Util::reftype $s; die $s } else {die Carp::longmess defined($s)? $s: "undef" }}; my $t = `pwd`; chop $t; $t .= '/' . __FILE__; my $s = '/tmp/.liveman/perl-aion-query!aion!query/'; `rm -fr '$s'` if -e $s; chdir _mkpath_($s) or die "chdir $s: $!"; open my $__f__, "<:utf8", $t or die "Read $t: $!"; read $__f__, $s, -s $__f__; close $__f__; while($s =~ /^#\@> (.*)\n((#>> .*\n)*)#\@< EOF\n/gm) { my ($file, $code) = ($1, $2); $code =~ s/^#>> //mg; open my $__f__, ">:utf8", _mkpath_($file) or die "Write $file: $!"; print $__f__ $code; close $__f__; } } # # NAME
# 
# Aion::Query - functional interface for accessing database mysql and mariadb
# 
# # VERSION
# 
# 0.0.0-prealpha
# 
# # SYNOPSIS
# 
# File config.pm:
#@> config.pm
#>> package config;
#>> 
#>> module_config Aion::Query => {
#>>     DRV  => "SQLite",
#>>     BASE => "test-base.sqlite",
#>> };
#>> 
#>> 1;
#@< EOF
# 
subtest 'SYNOPSIS' => sub { 
use Aion::Query;

query "CREATE TABLE author (
    id INT PRIMARY KEY AUTOINCREMENT,
    name STRING NOT NULL,
    books INT NOT NULL,
    UNIQUE name_unq (name)
)";

::is scalar do {insert "author", name => "Pushkin A.S."}, scalar do{1}, 'insert "author", name => "Pushkin A.S."     # -> 1';
::is scalar do {touch "author", name => "Pushkin A.S."}, scalar do{1}, 'touch "author", name => "Pushkin A.S."      # -> 1';
::is scalar do {touch "author", name => "Pushkin A."}, scalar do{2}, 'touch "author", name => "Pushkin A."        # -> 2';

::is scalar do {query "SELECT count(*) FROM author"}, scalar do{2}, 'query "SELECT count(*) FROM author"  # -> 2';

my @rows = query "SELECT * FROM author WHERE name like :name",
    name => "P%",
;

::is_deeply scalar do {\@rows}, scalar do {[{id => 1, name => "Pushkin A.S."}, {id => 2, name => "Pushkin A."}]}, '\@rows # --> [{id => 1, name => "Pushkin A.S."}, {id => 2, name => "Pushkin A."}]';

# 
# # DESCRIPTION
# 
# Functional interface for accessing database mysql or mariadb.
# 
# # SUBROUTINES
# 
# ## query ($query, %params)
# 
# It provide SQL (DCL, DDL, DQL and DML) queries to DBMS with quoting params.
# 
done_testing; }; subtest 'query ($query, %params)' => sub { 
::is scalar do {query "UPDATE author SET name=:name WHERE id=1", name => 'Pupkin I.'}, scalar do{1}, 'query "UPDATE author SET name=:name WHERE id=1", name => \'Pupkin I.\' # -> 1';

# 
# ## LAST_INSERT_ID ()
# 
# Returns last insert id.
# 
done_testing; }; subtest 'LAST_INSERT_ID ()' => sub { 
query "INSERT author SET name = :name", name => "Alice";
::is scalar do {LAST_INSERT_ID}, scalar do{2}, 'LAST_INSERT_ID  # -> 2';

# 
# ## quote ($scalar)
# 
# Quoted scalar for SQL-query.
# 
done_testing; }; subtest 'quote ($scalar)' => sub { 
::is scalar do {quote "abc"}, "'abc'", 'quote "abc"     # => \'abc\'';
::is scalar do {quote [1,2,"5"]}, "1,2,'5'", 'quote [1,2,"5"] # => 1,2,\'5\'';

::is_deeply scalar do {map quote, -6, "-6", 1.5, "1.5"}, scalar do {[-6, "'-6'", 1.5, "'1.5'"]}, 'map quote, -6, "-6", 1.5, "1.5" # --> [-6, "\'-6\'", 1.5, "\'1.5\'"]';

# 
# ## query_prepare ($query, %param)
# 
# Replace the parameters in `$query`. Parameters quotes by the `quote`.
# 
done_testing; }; subtest 'query_prepare ($query, %param)' => sub { 
::is scalar do {query_prepare "INSERT author SET name = :name", name => "Alice"}, "INSERT author SET name = 'Alice'", 'query_prepare "INSERT author SET name = :name", name => "Alice"  # => INSERT author SET name = \'Alice\'';

# 
# ## query_do ($query)
# 
# Execution query and returns it result.
# 
done_testing; }; subtest 'query_do ($query)' => sub { 
::is scalar do {query_do "SELECT count(*) FROM author"}, scalar do{2}, 'query_do "SELECT count(*) FROM author"  # -> 2';
::is_deeply scalar do {query_do "SELECT id FROM author WHERE id=2"}, scalar do {[{id=>2}]}, 'query_do "SELECT id FROM author WHERE id=2"  # --> [{id=>2}]';

# 
# ## query_ref ($query, %kw)
# 
# As `query`, but always returns a reference.
# 
done_testing; }; subtest 'query_ref ($query, %kw)' => sub { 
my @res = query_ref "SELECT id FROM author WHERE id=:id", id => 2;
::is_deeply scalar do {\@res}, scalar do {[[ {id=>2} ]]}, '\@res  # --> [[ {id=>2} ]]';

# 
# ## query_sth ($query, %kw)
# 
# As query, but returns `$sth`.
# 
done_testing; }; subtest 'query_sth ($query, %kw)' => sub { 
my $sth = query_sth "SELECT * FROM author";
my @rows;
while(my $row = $sth->selectall_arrayref) {
    push @rows, $row;
}
$sth->final;

::is scalar do {0+@rows}, scalar do{3}, '0+@rows  # -> 3';

# 
# ## query_slice ($key, $val, @args)
# 
# .
# 
done_testing; }; subtest 'query_slice ($key, $val, @args)' => sub { 
::is scalar do {query_slice($key, $val, @args)}, scalar do{.3}, 'query_slice($key, $val, @args)  # -> .3';

# 
# ## query_col ()
# 
# .
# 
done_testing; }; subtest 'query_col ()' => sub { 
::is scalar do {query_col}, scalar do{.3}, 'query_col  # -> .3';

# 
# ## query_row ()
# 
# 
# 
done_testing; }; subtest 'query_row ()' => sub { 
::is scalar do {query_row}, scalar do{.3}, 'query_row  # -> .3';

# 
# ## query_row_ref ()
# 
# 
# 
done_testing; }; subtest 'query_row_ref ()' => sub { 
::is scalar do {query_row_ref}, scalar do{.3}, 'query_row_ref  # -> .3';

# 
# ## query_scalar ()
# 
# 
# 
done_testing; }; subtest 'query_scalar ()' => sub { 
::is scalar do {query_scalar}, scalar do{.3}, 'query_scalar  # -> .3';

# 
# ## make_query_for_order ($order, $next)
# 
# 
# 
done_testing; }; subtest 'make_query_for_order ($order, $next)' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->make_query_for_order($order, $next)}, scalar do{.3}, '$aion_query->make_query_for_order($order, $next)  # -> .3';

# 
# ## settings ($id, $value)
# 
# Устанавливает или возвращает ключ из таблицы settings
# 
done_testing; }; subtest 'settings ($id, $value)' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->settings($id, $value)}, scalar do{.3}, '$aion_query->settings($id, $value)  # -> .3';

# 
# ## load_by_id ($tab, $pk, $fields, @options)
# 
# возвращает запись по её pk
# 
done_testing; }; subtest 'load_by_id ($tab, $pk, $fields, @options)' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->load_by_id($tab, $pk, $fields, @options)}, scalar do{.3}, '$aion_query->load_by_id($tab, $pk, $fields, @options)  # -> .3';

# 
# ## insert ($tab, %x)
# 
# Добавляет запись и возвращает её id
# 
done_testing; }; subtest 'insert ($tab, %x)' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->insert($tab, %x)}, scalar do{.3}, '$aion_query->insert($tab, %x)  # -> .3';

# 
# ## update ($tab, $id, %x)
# 
# 
# 
done_testing; }; subtest 'update ($tab, $id, %x)' => sub { 
::is scalar do {update($tab, $id, %x)}, scalar do{.3}, 'update($tab, $id, %x)  # -> .3';

# 
# ## remove ($tab, $id)
# 
# Remove row from table by it id, and returns id.
# 
done_testing; }; subtest 'remove ($tab, $id)' => sub { 
::is scalar do {remove "author", 6}, scalar do{6}, 'remove "author", 6  # -> 6';

# 
# ## query_id ()
# 
# 
# 
done_testing; }; subtest 'query_id ()' => sub { 
::is scalar do {query_id}, scalar do{.3}, 'query_id  # -> .3';

# 
# ## stores ($tab, $rows, %opt)
# 
# 
# 
done_testing; }; subtest 'stores ($tab, $rows, %opt)' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->stores($tab, $rows, %opt)}, scalar do{.3}, '$aion_query->stores($tab, $rows, %opt)  # -> .3';

# 
# ## store ()
# 
# 
# 
done_testing; }; subtest 'store ()' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->store}, scalar do{.3}, '$aion_query->store  # -> .3';

# 
# ## touch ()
# 
# Сверхмощная функция: возвращает pk, а если его нет - создаёт или обновляет запись и всё равно возвращает
# 
done_testing; }; subtest 'touch ()' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->touch}, scalar do{.3}, '$aion_query->touch  # -> .3';

# 
# ## START_TRANSACTION ()
# 
# возвращает переменную, на которой нужно установить commit, иначе происходит откат
# 
done_testing; }; subtest 'START_TRANSACTION ()' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->START_TRANSACTION}, scalar do{.3}, '$aion_query->START_TRANSACTION  # -> .3';

# 
# ## default_dsn ()
# 
# Default DSN for `DBI->connect`.
# 
done_testing; }; subtest 'default_dsn ()' => sub { 
::is scalar do {default_dsn}, "123", 'default_dsn  # => 123';

# 
# ## default_connect_options ()
# 
# DSN, USER, PASSWORD and commands after connect.
# 
done_testing; }; subtest 'default_connect_options ()' => sub { 
::is_deeply scalar do {[default_connect_options]}, scalar do {[]}, '[default_connect_options]  # --> []';

# 
# ## base_connect ($dsn, $user, $password, $conn)
# 
# Connect to base and returns connect and it identify.
# 
done_testing; }; subtest 'base_connect ($dsn, $user, $password, $conn)' => sub { 
my ($dbh, $connect_id) = base_connect("", "toor", "toorpasswd", [
    "SET NAMES utf8",
    "SET sql_mode='NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'",
]);

::is scalar do {ref $dbh}, "123", 'ref $dbh     # => 123';
::is scalar do {$connect_id}, scalar do{123}, '$connect_id  # -> 123';

# 
# ## connect_respavn ($base)
# 
# Connection check and reconnection.
# 
done_testing; }; subtest 'connect_respavn ($base)' => sub { 
::is scalar do {connect_respavn($base)}, scalar do{.3}, 'connect_respavn($base)  # -> .3';

# 
# ## connect_restart ($base)
# 
# Рестарт коннекта
# 
done_testing; }; subtest 'connect_restart ($base)' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->connect_restart($base)}, scalar do{.3}, '$aion_query->connect_restart($base)  # -> .3';

# 
# ## query_stop ()
# 
# возможно выполняется запрос - нужно его убить
# 
done_testing; }; subtest 'query_stop ()' => sub { 
my $aion_query = Aion::Query->new;
::is scalar do {$aion_query->query_stop}, scalar do{.3}, '$aion_query->query_stop  # -> .3';

# 
# ## sql_debug ($fn, $query)
# 
# .
# 
done_testing; }; subtest 'sql_debug ($fn, $query)' => sub { 
::is scalar do {sql_debug($fn, $query)}, scalar do{.3}, 'sql_debug($fn, $query)  # -> .3';

# 
# # AUTHOR
# 
# Yaroslav O. Kosmina [dart@cpan.org](dart@cpan.org)
# 
# # LICENSE
# 
# ⚖ **GPLv3**
# 
# # COPYRIGHT
# 
# The Aion::Surf module is copyright © 2023 Yaroslav O. Kosmina. Rusland. All rights reserved.

	done_testing;
};

done_testing;
