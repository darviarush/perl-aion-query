# NAME

Aion::Query - functional interface for accessing database mysql and mariadb

# VERSION

0.0.0-prealpha

# SYNOPSIS

File config.pm:
```perl
package config;

module_config Aion::Query => {
    DRV  => "SQLite",
    BASE => "test-base.sqlite",
};

1;
```

```perl
use Aion::Query;

query "CREATE TABLE author (
    id INT PRIMARY KEY AUTOINCREMENT,
    name STRING NOT NULL,
    books INT NOT NULL,
    UNIQUE name_unq (name)
)";

insert "author", name => "Pushkin A.S." # -> 1
touch "author", name => "Pushkin A."    # -> 2
touch "author", name => "Pushkin A.S."  # -> 1
touch "author", name => "Pushkin A."    # -> 2

query "SELECT count(*) FROM author"  # -> 2

my @rows = query "SELECT * FROM author WHERE name like :name",
    name => "P%",
;

\@rows # --> [{id => 1, name => "Pushkin A.S."}, {id => 2, name => "Pushkin A."}]
```

# DESCRIPTION

DBI is awkward to use. This module contains abbreviations that will help you focus on writing programs, making programs short and understandable.

# SUBROUTINES

## query ($query, %params)

It provide SQL (DCL, DDL, DQL and DML) queries to DBMS with quoting params.

```perl
query "UPDATE author SET name=:name WHERE id=1", name => 'Pupkin I.' # -> 1
```

## LAST_INSERT_ID ()

Returns last insert id.

```perl
query "INSERT author SET name = :name", name => "Alice";
LAST_INSERT_ID  # -> 2
```

## quote ($scalar)

Quoted scalar for SQL-query.

```perl
quote "abc"     # => 'abc'
quote [1,2,"5"] # => 1,2,'5'

map quote, -6, "-6", 1.5, "1.5" # --> [-6, "'-6'", 1.5, "'1.5'"]
```

## query_prepare ($query, %param)

Replace the parameters in `$query`. Parameters quotes by the `quote`.

```perl
query_prepare "INSERT author SET name = :name", name => "Alice"  # => INSERT author SET name = 'Alice'
```

## query_do ($query)

Execution query and returns it result.

```perl
query_do "SELECT count(*) FROM author"  # -> 2
query_do "SELECT id FROM author WHERE id=2"  # --> [{id=>2}]
```

## query_ref ($query, %kw)

As `query`, but always returns a reference.

```perl
my @res = query_ref "SELECT id FROM author WHERE id=:id", id => 2;
\@res  # --> [[ {id=>2} ]]
```

## query_sth ($query, %kw)

As `query`, but returns `$sth`.

```perl
my $sth = query_sth "SELECT * FROM author";
my @rows;
while(my $row = $sth->selectall_arrayref) {
    push @rows, $row;
}
$sth->final;

0+@rows  # -> 3
```

## query_slice ($key, $val, @args)

As query, plus converts the result into the desired data structure.

```perl
my %author = query_slice name => "id", "SELECT id, name FROM author";
\%author  # --> {"Pushkin A.S." => 1, "Pushkin A." => 2}
```

## query_col ()

Returns one column.

```perl
query_col "SELECT name FROM author ORDER BY name" # --> ["Pushkin A.", "Pushkin A.S."]
```

## query_row ()

Returns one row.

```perl
query_row  # -> .3
```

## query_row_ref ()



```perl
query_row_ref  # -> .3
```

## query_scalar ()

Returns scalar.

```perl
query_scalar "SELECT name FROM author WHERE id=2" # => Pushkin S.
```

## make_query_for_order ($order, $next)



```perl
make_query_for_order($order, $next)  # -> .3
```

## settings ($id, $value)

Устанавливает или возвращает ключ из таблицы settings

```perl
query "CREATE TABLE sessings(

)";


settings($id, $value)  # -> .3
```

## load_by_id ($tab, $pk, $fields, @options)

возвращает запись по её pk

```perl
my $aion_query = Aion::Query->new;
$aion_query->load_by_id($tab, $pk, $fields, @options)  # -> .3
```

## insert ($tab, %x)

Добавляет запись и возвращает её id

```perl
my $aion_query = Aion::Query->new;
$aion_query->insert($tab, %x)  # -> .3
```

## update ($tab, $id, %x)



```perl
update($tab, $id, %x)  # -> .3
```

## remove ($tab, $id)

Remove row from table by it id, and returns id.

```perl
remove "author", 6  # -> 6
```

## query_id ()



```perl
query_id  # -> .3
```

## stores ($tab, $rows, %opt)



```perl
my $aion_query = Aion::Query->new;
$aion_query->stores($tab, $rows, %opt)  # -> .3
```

## store ()



```perl
my $aion_query = Aion::Query->new;
$aion_query->store  # -> .3
```

## touch ()

Сверхмощная функция: возвращает pk, а если его нет - создаёт или обновляет запись и всё равно возвращает

```perl
my $aion_query = Aion::Query->new;
$aion_query->touch  # -> .3
```

## START_TRANSACTION ()

возвращает переменную, на которой нужно установить commit, иначе происходит откат

```perl
my $aion_query = Aion::Query->new;
$aion_query->START_TRANSACTION  # -> .3
```

## default_dsn ()

Default DSN for `DBI->connect`.

```perl
default_dsn  # => 123
```

## default_connect_options ()

DSN, USER, PASSWORD and commands after connect.

```perl
[default_connect_options]  # --> []
```

## base_connect ($dsn, $user, $password, $conn)

Connect to base and returns connect and it identify.

```perl
my ($dbh, $connect_id) = base_connect("", "toor", "toorpasswd", [
    "SET NAMES utf8",
    "SET sql_mode='NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'",
]);

ref $dbh     # => 123
$connect_id  # -> 123
```

## connect_respavn ($base)

Connection check and reconnection.

```perl
connect_respavn($base)  # -> .3
```

## connect_restart ($base)

Рестарт коннекта

```perl
my $aion_query = Aion::Query->new;
$aion_query->connect_restart($base)  # -> .3
```

## query_stop ()

возможно выполняется запрос - нужно его убить

```perl
my $aion_query = Aion::Query->new;
$aion_query->query_stop  # -> .3
```

## sql_debug ($fn, $query)

.

```perl
sql_debug($fn, $query)  # -> .3
```

# AUTHOR

Yaroslav O. Kosmina [dart@cpan.org](dart@cpan.org)

# LICENSE

⚖ **GPLv3**

# COPYRIGHT

The Aion::Surf module is copyright © 2023 Yaroslav O. Kosmina. Rusland. All rights reserved.
