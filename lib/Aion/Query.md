# NAME

Aion::Query - functional interface for accessing database mysql and mariadb

# VERSION

0.0.0-prealpha

# SYNOPSIS

File .config.pm:
```perl
package config;

config_module Aion::Query => {
    DRV  => "SQLite",
    BASE => "test-base.sqlite",
    BQ => 0,
};

1;
```

```perl
use Aion::Query;

query "CREATE TABLE author (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
)";

insert "author", name => "Pushkin A.S." # -> 1

touch "author", name => "Pushkin A."    # -> 2
touch "author", name => "Pushkin A.S."  # -> 1
touch "author", name => "Pushkin A."    # -> 2

query_scalar "SELECT count(*) FROM author"  # -> 2

my @rows = query "SELECT *
FROM author
WHERE 1
    if_name>> AND name like :name
",
    if_name => Aion::Query::BQ == 0,
    name => "P%",
;

\@rows # --> [{id => 1, name => "Pushkin A.S."}, {id => 2, name => "Pushkin A."}]

$Aion::Query::DEBUG[1]  # => query: INSERT INTO author (name) VALUES ('Pushkin A.S.')
```

# DESCRIPTION

When constructing queries, many disparate conditions are used, usually separated by different methods.

`Aion::Query` uses a different approach, which allows you to construct an SQL query in a query using a simple template engine.

The second problem is placing unicode characters into single-byte encodings, which reduces the size of the database. So far it has been solved only for the **cp1251** encoding. It is controlled by the parameter `BQ = 1`.

# SUBROUTINES

## query ($query, %params)

It provide SQL (DCL, DDL, DQL and DML) queries to DBMS with quoting params and .

```perl
query "SELECT * FROM author WHERE name=:name", name => 'Pushkin A.S.' # --> [{id=>1, name=>"Pushkin A.S."}]
```

## LAST_INSERT_ID ()

Returns last insert id.

```perl
query "INSERT INTO author (name) VALUES (:name)", name => "Alice"  # -> 1
#LAST_INSERT_ID  # -> 3
```

## quote ($scalar)

Quoted scalar for SQL-query.

```perl
quote "abc"     # => 'abc'
quote 123       # => 123
quote "123"     # => '123'
quote [1,2,"5"] # => 1, 2, '5'

[map quote, -6, "-6", 1.5, "1.5"] # --> [-6, "'-6'", 1.5, "'1.5'"]

quote \"without quote"  # => without quote
```

## query_prepare ($query, %param)

Replace the parameters in `$query`. Parameters quotes by the `quote`.

```perl
query_prepare "INSERT author SET name = :name", name => "Alice"  # => INSERT author SET name = 'Alice'
```

## query_do ($query)

Execution query and returns it result.

```perl
query_do "SELECT count(*) as n FROM author"  # --> [{n=>3}]
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
while(my $row = $sth->fetchrow_arrayref) {
    push @rows, $row;
}
$sth->finish;

0+@rows  # -> 3
```

## query_slice ($key, $val, @args)

As query, plus converts the result into the desired data structure.

```perl
my %author = query_slice name => "id", "SELECT id, name FROM author";
\%author  # --> {"Pushkin A.S." => 1, "Pushkin A." => 2, "Alice" => 3}
```

## query_col ($query, %params)

Returns one column.

```perl
query_col "SELECT name FROM author ORDER BY name" # --> ["Alice", "Pushkin A.", "Pushkin A.S."]

eval {query_col "SELECT id, name FROM author"}; $@  # ~> Only one column is acceptable!
```

## query_row ($query, %params)

Returns one row.

```perl
query_row "SELECT name FROM author WHERE id=2" # --> {name => "Pushkin A."}

my ($id, $name) = query_row "SELECT id, name FROM author WHERE id=2";
$id    # -> 2
$name  # => Pushkin A.
```

## query_row_ref ($query, %params)

As `query_row`, but retuns array reference always.

```perl
my @x = query_row_ref "SELECT name FROM author WHERE id=2";
\@x # --> [{name => "Pushkin A."}]

eval {query_row_ref "SELECT name FROM author"}; $@  # ~> A few lines!
```

## query_scalar ($query, %params)

Returns scalar.

```perl
query_scalar "SELECT name FROM author WHERE id=2" # => Pushkin A.
```

## make_query_for_order ($order, $next)

Creates a condition for requesting a page not by offset, but by **cursor pagination**.

To do this, it receives `$order` of the SQL query and `$next` - a link to the next page.

```perl
my ($select, $where, $order_sel) = make_query_for_order "name DESC, id ASC", undef;

$select     # => concat(name,',',id)
$where      # -> 1
$order_sel  # -> undef

my @rows = query "SELECT $select as next FROM author WHERE $where LIMIT 2";

my $last = pop @rows;

($select, $where, $order_sel) = make_query_for_order "name DESC, id ASC", $last->{next};
$select     # => concat(name,',',id)
$where      # -> 1
$order_sel  # -> undef
```

See also:
1. Article [Paging pages on social networks
](https://habr.com/ru/articles/674714/).
2. [SQL::SimpleOps->SelectCursor](https://metacpan.org/dist/SQL-SimpleOps/view/lib/SQL/SimpleOps.pod#SelectCursor)

## settings ($id, $value)

Sets or returns a key from a table `settings`.

```perl
query "CREATE TABLE sessings(
    id TEXT PRIMARY KEY,
	value TEXT NOT NULL
)";

settings "x1", 10;
settings "x1"  # -> 10
```

## load_by_id ($tab, $pk, $fields, @options)

Returns the entry by its id.

```perl
load_by_id author => 2  # --> {id=>2, name=>"Pushkin A."}
load_by_id author => 2, "name as n"  # --> {n=>"Pushkin A."}
load_by_id author => 2, "id+:x as n", x => 10  # --> {n=>12}
```

## insert ($tab, %x)

Adds a record and returns its id.

```perl
insert 'author', name => 'Masha'  # -> 3
```

## update ($tab, $id, %params)

Updates a record by its id, and returns this id.

```perl
update author => 3, name => 'Sasha'  # -> 3
eval { update author => 4, name => 'Sasha' }; $@  # ~> Row author.id=4 is not!
```

## remove ($tab, $id)

Remove row from table by it id, and returns this id.

```perl
remove "author", 3  # -> 3
eval { remove author => 3 }; $@  # ~> Row author.id=4 does not exist!
```

## query_id ($tab, %params)

Returns the id based on other fields.

```perl
query_id 'author', name => 'Pushkin A.' # -> 2
```

## stores ($tab, $rows, %opt)

Saves data (update or insert).

```perl
my @authors = (
    {id => 1, name => 'Pushkin A.S.'},
    {id => 2, name => 'Pushkin A.'},
);

query "SELECT * FROM author ORDER BY id" # --> \@authors

my $rows = stores 'author', [
    {name => 'Locatelli'},
    {id => 3, name => ''},
    {id => 2, name => 'Pushkin A.'},
];
$rows  # -> 2

@authors = (
    {id => 1, name => 'Pushkin A.S.'},
    {id => 2, name => 'Pushkin A.'},
);

```

## store ($tab, %params)

Saves data (update or insert). But one row.

```perl
store 'author', name => 'Bishop M.' # -> 1
```

## touch ()

Super-powerful function: returns id of row, and if it doesn’t exist, creates or updates a row and still returns.

```perl
touch name => 'Pushkin A.' # -> 2
touch name => 'Pushkin X.' # -> 5
```

## START_TRANSACTION ()

Returns the variable on which to set commit, otherwise the rollback occurs.

```perl
my $transaction = START_TRANSACTION;

ref $transaction # => 123

undef $transaction;
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
ref $Aion::Query::base            # => 123
$Aion::Query::base_connection_id  # ~> ^\d+$

connect_respavn $Aion::Query::base, $Aion::Query::base_connection_id  # -> .3
```

## connect_restart ($base)

Connection restart.

```perl
my $connection_id = $Aion::Query::base_connection_id;
my $base = $Aion::Query::base;

connect_restart $Aion::Query::base, $Aion::Query::base_connection_id;

$connection_id != $Aion::Query::base_connection_id  # -> 1
$base->ping  # -> ""
$Aion::Query::base->ping  # -> 1
```

## query_stop ()

A request may be running - you need to kill it.

Creates an additional connection to the base and kills the main one.

```perl
my @x = query_stop;
\@x  # --> []
```

## sql_debug ($fn, $query)

Stores queries to the database in `@Aion::Query::DEBUG`. Called from `query_do`.

```perl
sql_debug label => "SELECT 123";

$Aion::Query::DEBUG[$#Aion::Query::DEBUG]  # => label: SELECT 123"
```

# AUTHOR

Yaroslav O. Kosmina [dart@cpan.org](dart@cpan.org)

# LICENSE

⚖ **GPLv3**

# COPYRIGHT

The Aion::Surf module is copyright © 2023 Yaroslav O. Kosmina. Rusland. All rights reserved.
