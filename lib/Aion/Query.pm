package Aion::Query;
use 5.22.0;
no strict; no warnings; no diagnostics;
use common::sense;

our $VERSION = "0.0.0-prealpha";

use B;

use Exporter qw/import/;
our @EXPORT = our @EXPORT_OK = grep {
	*Aion::Query{$_}{CODE} && !/^(_|(NaN|import)\z)/n
} keys %Aion::Query;

use config {
	DSN  => undef,
    DRV  => 'mysql',
    BASE => 'BASE',
    HOST => undef,
    PORT => undef,
    SOCK => undef,
    USER => 'root',
    PASS => 123,
    CONN => undef,
    DEBUG => 0,
};

# Формирует DSN на основе конфига
our $DEFAULT_DSN;
sub default_dsn() {
	$DEFAULT_DSN //= do {
		if(defined DSN) {DSN}
		elsif(DRV =~ /mysql|mariadb/i) {
			my $sock = SOCK;
			$sock //= "/var/run/mysqld/mysqld.sock" if !defined HOST;

			"DBI:${\ DRV}:database=${\ BASE};${\(defined(HOST)?
				'host=' . HOST . (defined(PORT)? ':' . PORT: ()) . ';': ())
			}${\ defined($sock)? 'mysql_socket=' . $sock: ()}"
		}
		elsif(DRV =~ /sqlite/i) { "DBI:${\ DRV}:dbname=${\ BASE}" }
		else { die "Using DSN! DRV: ${\ DRV} is'nt supported." }
	}
}

my $CONN;
sub default_connect_options() {
    return default_dsn, USER, PASS, $CONN //= CONN // do {
		if(DRV =~ /mysql|mariadb/i) {[
			"SET NAMES utf8",
			"SET sql_mode='NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'",
   		]}
	};
}

# Коннект к базе и id коннекта
sub base_connect {
	my ($dsn, $user, $password, $conn) = @_;
	my $base = DBI->connect($dsn, $user, $password, {
		RaiseError => 1,
		PrintError => 0,
		$dsn =~ /^DBI:mysql/i ? (mysql_enable_utf8 => 1): (),
	}) or die "Connect to db failed";

	$base->do($_) for @$conn;
	return $base unless wantarray;
	my ($base_connection_id) = $base->selectrow_array("SELECT connection_id()");
	return $base, $base_connection_id;
}

# Проверка коннекта и переконнект
sub connect_respavn {
	my ($base) = @_;
	$base->disconnect, undef $base if $base and !$base->ping;
	($_[0], $_[1]) = base_connect(default_connect_options) if !$base;
	return;
}

# Рестарт коннекта
sub connect_restart {
	my ($base) = @_;
	$base->disconnect if $base;
	$_[0] = base_connect(default_connect_options());
	return;
}


# Инициализация БД
our $base; our $base_connection_id;

END {
	$base->disconnect if $base;
}

# возможно выполняется запрос - нужно его убить
sub query_stop {
	# вспомогательное подключение
	my $signal = base_connect(default_connect_options());
	$signal->do("KILL HARD " . ($base_connection_id + 0));
	$signal->disconnect;
	return;
}

# Запросы к базе

our @DEBUG;
sub sql_debug(@) {
	my ($fn, $query) = @_;
	my $msg = "$fn: " . (ref $query? np($query): $query);
	push @DEBUG, $msg;
	print STDERR $msg, "\n" if DEBUG;
}

# sub debug_html {
# 	join "", map { ("<p class='debug'>", to_html($_), "</p>\n") } @DEBUG;
# }

# sub debug_text {
# 	return "" if !@DEBUG;
# 	join "", map { "$_\n\n" } @DEBUG, "";
# }

# sub debug_array {
# 	return if !@DEBUG;
# 	$_[0]->{SQL_DEBUG} = \@DEBUG;
# 	return;
# }


sub LAST_INSERT_ID() {
	query_scalar("SELECT LAST_INSERT_ID()");
}

# Преобразует в строку
sub _to_str($) {
	local($_) = @_;
	s/[\\']/\\$&/g;
	s/^(.*)\z/'$1'/s;
	$_
}

# Преобразует в бинарную строку принятую в MYSQL
sub _to_hex_str($) {
	my ($s) = @_;
	no utf8;
	use bytes;
	$s =~ s/./sprintf "%02X", ord $&/gaes;
	"X'$s'"
}

# Идея перекодирования символов:
# В базе используется cp1251, поэтому символы, которые в неё не входят, нужно перевести в последовательности.
# Вид последовательности: °ЧИСЛО_В_254-ричной системе; \x7F
# Знак ° выбран потому, что он выше 127, соответственно строка из базы данных, содержащая такую последовательность,
# будет с флагом utf8, что необходимо для обратного перекодирования.
sub _recode_cp1251 {
	my ($s) = @_;
	our $CIF;
	$s =~ s/°|[^\Q$CIF\E]/"°${\ to_radix(ord $&, 254) }\x7F"/ge;
	$s
}

sub quote(;$);
sub quote(;$) {
	my ($k) = @_ == 0? $_: @_;

	!defined($k)? "NULL":
	ref $k eq "ARRAY" && ref $k->[0] eq "ARRAY"? join(", ", map { join "", "(", join(", ", map { quote($_) } @$_), ")" } @$k):
	ref $k eq "ARRAY"? join("", join(", ", map { quote($_) } @$k)):
	ref $k eq "HASH"? join(" ", map { join " ", "WHEN", quote($_), "THEN", quote($k->{$_}) } sort keys %$k):
	ref $k eq "REF" && ref $$k eq "HASH"? join(", ", map { join "", $_, " = ", quote($$k->{$_}) } sort keys %$$k):
	ref $k eq "SCALAR"? $$k:
	Scalar::Util::blessed($k)? $k:
	$k =~ /^-?(0|[1-9]\d*)(\.\d+)?\z/an && B::svref_2object(\$k) ne "B::PV"? $k:
	!utf8::is_utf8($k)? (
		$k =~ /[\x80-\xFF]/a ? _to_hex_str($k): #$base->quote($k, DBI::SQL_BINARY):
			_to_str($k)
	):
	_to_str(_recode_cp1251($k))
}

sub query_prepare (@) {
	my ($query, %param) = @_;

	$query =~ s!^[ \t]*(\w+)>>(.*\n?)!$param{$1}? $2: ""!mge;
	#$query =~ s!^[ \t]*(\w+)\*>(.*\n?)!$param{$1}? join("", map {  } @{$param{$1}}): ""!mge;
	$query =~ s!:([a-z_]\w*)! exists $param{$1}? quote($param{$1}): die "The :$1 parameter was not passed."!ige;

	$query
}

sub query_do($) {
	my ($query) = @_;
	sql_debug query => $query;
	connect_respavn($base, $base_connection_id);

	my $res = eval {
		if($query =~ /^\s*(select|show|desc(ribe)?)\b/in) {

			my $r = $base->selectall_arrayref($query, { Slice => {} });

			if(defined $r) {
				for my $row (@$r) {
					for my $k (keys %$row) {
						$row->{$k} =~ s/°([^\x7F]{1,7})\x7F/chr from_radix($1, 254)/ge if utf8::is_utf8($row->{$k});
					}
				}
			}
			$r
		} else {
			0 + $base->do($query)
		}
	};
	die "$@\n" . (length($query)>$main_config::max_query_error? substr($query, 0, $main_config::max_query_error) . " ...": $query) if $@;

	$res
}

sub query_ref(@) {
	my ($query, %kw) = @_;
	my $map = delete $kw{MAP};
	$query = query_prepare($query, %kw) if @_>1;
	my $res = query_do($query);
	if($map && ref $res eq "ARRAY") {
		include $map;
		[map { $map->new(%$_) } @$res]
	} else {
		$res
	}
}

sub query(@) {
	my $ref = query_ref(@_);
	wantarray && ref $ref? @$ref: $ref;
}

sub query_sth(@) {
	my ($query, %kw) = @_;
	$query = query_prepare($query, %kw) if @_>1;
	my $sth = $base->prepare($query);
	$sth->execute;
	$sth
}

# Для слайса
#
#	query_slice word => "id", "SELECT word, id FROM word WHERE word in (1,2,3)" 	-> 	{ 1 => 10, 2 => 20 }
#
# 	query_slice word => {}, "SELECT word, id FROM word WHERE word in (1,2,3)" 		-> 	{ 1 => {id => 10, word => 1} }
#
#	query_slice word => ["id"], "SELECT word, id FROM word WHERE word in (1,2,3)" 	-> 	{ 1 => [10, 20], 2 => [30] }
#
# 	query_slice word => [], "SELECT word, id FROM word WHERE word in (1,2,3)" 		-> 	{ 1 => [{id => 10, word => 1}, {id => 20, word => 2}] }
#
# 	query_slice word => [[]], "SELECT word, id FROM word WHERE word in (1,2,3)" 		-> [ [{id => 10, word => 1}, {id => 20, word => 2}], ... ]
#
# 	TODO: query_slice [] => word, "SELECT word, id FROM word WHERE word in (1,2,3)" 		-> 	[{id => 10, word => 1}, {id => 20, word => 2}]
#
#   TODO: [ "id", "name", "jinni" ] -> [{ id=>1, items => [{ name => "hi!", items => [{ jinni=>2, items => [{...}] }] }] }]
#
sub query_slice(@);
sub query_slice(@) {
	my ($key, $val, @args) = @_;

	my $is_array = ref $val eq "ARRAY" && @$val && ref $val->[0] eq "ARRAY";

	return $is_array? [ query_slice @_ ]: +{ query_slice @_ } if !wantarray;

	my $rows = query_ref(@args);

	if($is_array) {
		my %x; my @x;
		for(@$rows) {
			my $k = $_->{$key};
			push @x, $x{$k} = [] if !exists $x{$k};
			push @{$x{$k}}, $_;
		}
		@x
	}
	elsif(ref $val eq "HASH") {
		map { $_->{$key} => $_ } @$rows
	}
	elsif(ref $val eq "ARRAY") {
		if(@$val) {
			my $col = $val->[0];
			my %x;
			push @{$x{$_->{$key}}}, $_->{$col} for @$rows;
			%x
		} else {
			my %x;
			push @{$x{$_->{$key}}}, $_ for @$rows;
			%x
		}
	}
	else {
		map { $_->{$key} => $_->{$val} } @$rows
	}
}

# Выбрать один колумн
#
#   query_col "SELECT id FROM word WHERE word in (1,2,3)" 	-> 	[1,2,3]
#
sub query_col(@);
sub query_col(@) {
	return [query_col @_] if !wantarray;

	my $rows = query_ref(@_);
	die "Приемлем только один столбец!" if @$rows and 1 != keys %{$rows->[0]};

	map { my ($k, $v) = %$_; $v } @$rows
}

# Выбрать строку
#
#   query_row_ref "SELECT id, word FROM word WHERE word = 1" 	-> 	{id=>1, word=>"серебро"}
#
sub query_row_ref(@) {
	my $rows = query_ref(@_);
	die "Несколько строк!" if @$rows>1;
	$rows->[0]
}

# Выбрать строку
#
#   ($id, $word) = query_row_ref "SELECT id, word FROM word WHERE word = 1"
#
sub query_row(@) {
	my $row = query_row_ref(@_);
	return wantarray? values(%$row): $row
}

# Выбрать значение
#
#   query_scalar "SELECT word FROM word WHERE id = 1" 	-> 	"золото"
#
sub query_scalar(@) {
	my $rows = query_ref(@_);
	die "Несколько строк!" if @$rows>1;
	die "Приемлем только один столбец! " . keys %{$rows->[0]} if @$rows and 1 != keys %{$rows->[0]};
	my ($k, $v) = %{$rows->[0]};
	$v
}

# Создаёт части sql-запроса для сортировки по условию, а не лимиту
#
# ("concat(size,',',likes)", "(size < 10 OR size = 10 AND likes >= 12)", ["size", "likes"]) = make_query_for_order "size desc, likes", "10,12"
#
# ("concat(size,',',likes)", 1) = make_query_for_order "size desc, likes", ""
#
sub make_query_for_order(@) {
	my ($order, $next) = @_;

	my @orders = split /\s*,\s*/, $order;
	my @order_direct;
	my @order_sel = map { my $x=$_; push @order_direct, $x=~s/\s+(asc|desc)\s*$//e ? $1: "asc"; $x } @orders;

	my $select = @order_sel==1? $order_sel[0]: join "", "concat(", join(",',',", @order_sel), ")";

	return $select, 1 if $next eq "";

	my @next = split /,/, $next;
	$next[$#orders] //= "";
	@next = map quote($_), @next;
	my @op = map { /^a/ ? ">": "<" } @order_direct;

	# id -> id >= next[0]
	# id, update -> id > next[0] OR id = next[0] and
	my @whr;
	for(my $i=0; $i<@orders; $i++) {
		my @opr;
		for(my $j=0; $j<=$i; $j++) {
			my $eq = $j == $#orders? "=": "";
			if($j != $i) {
				push @opr, "$order_sel[$j] = $next[$j]";
			} elsif($j != $#orders) {
				push @opr, "$order_sel[$j] $op[$j] $next[$j]";
			} else {
				push @opr, "$order_sel[$j] $op[$j]= $next[$j]";
			}
		}
		push @whr, join " AND ", @opr;
	}
	my $where = join "\nOR ", map "$_", @whr;

	return $select, "($where)", \@order_sel;
}

# Устанавливает или возвращает ключ из таблицы settings
sub settings($;$) {
	my ($id, $value) = @_;
	if(@_ == 1) {
		my $v = query_scalar("SELECT value FROM settings WHERE id=:id", id => $id);
		return defined($v)? from_json($v): $v;
	}

	return remove("settings" => $id) if !defined $value;

	query("INSERT INTO settings (id, value) VALUES (:id, :value) ON DUPLICATE KEY UPDATE value=values(value)",
		id => $id,
		value => to_json($value),
	);
}

# возвращает запись по её pk
sub load_by_id(@) {
	my ($tab, $pk, $fields, @options) = @_;
	$fields //= "*";
	query_row("SELECT $fields FROM $tab WHERE id=:id LIMIT 2", @options, id=>$pk)
}

# Добавляет запись и возвращает её id
sub insert(@) {
	my ($tab, %x) = @_;
	query "INSERT INTO $tab SET :set", set => \\%x;
	LAST_INSERT_ID()
}

# Обновляет запись по её id
#
#	update "tab" => 123, word => 123 						-> 6
#
sub update(@) {
	my ($tab, $id, %x) = @_;
	die "Записи с $tab.id=$id — нет." if !query "UPDATE $tab SET :set WHERE id=:id", id=>$id, set => \\%x;
	$id
}

# Удаляет запись по её id
#
#	remove "tab" => 123 		-> 123
#
sub remove(@) {
	my ($tab, $id) = @_;
	die "Row $tab.id=$id does not exist!" if !query "DELETE FROM $tab WHERE id=:id", id=>$id;
	$id
}

# Возвращает ключ по другим полям
#
#	query_id "tab", word => 123 						-> 6
#
sub query_id(@) {
	my $tab = shift; my %row = @_;

	my $pk = delete($row{'-pk'}) // "id";
	my $fields = ref $pk? join(", ", @$pk): $pk;

	my $where = join " AND ", map { my $v = $row{$_}; defined($v)? "$_ = ${\ quote($v) }": "$_ is NULL" } sort keys %row;
	my $query = "SELECT $fields FROM $tab WHERE $where LIMIT 2";

	my $v = query_row($query);

	ref $pk? $v: $v->{$pk}
}

# сохраняет данные (update или insert)
#
#	stores "tab", [{word=>1}, {word=>2}];
#
sub stores(@) {
	my ($tab, $rows, %opt) = @_;

	my @keys = sort keys %{$rows->[0]};
	die "No fields in bean $tab!" if !@keys;

	my $fields = join ", ", @keys;

	my $values = join ",\n", map { my $row = $_; join "", "(", quote([map $row->{$_}, @keys]), ")" } @$rows;

	if($opt{insert} || $opt{ignore}) {
		my $ignore = $opt{ignore}? "IGNORE ": "";
		my $query = "INSERT ${ignore}INTO $tab ($fields) VALUES $values";
		return query_do($query);
	}

	my $fupdate = join ", ", map "$_ = values($_)", @keys;

	my $query = "INSERT INTO $tab ($fields) VALUES $values ON DUPLICATE KEY UPDATE $fupdate";

	query_do($query)
}

# сохраняет данные (update или insert)
#
#	store "tab", word=>123;
#
sub store (@) {
	my $tab = shift;
	stores $tab, [+{@_}];
}

# Сверхмощная функция: возвращает pk, а если его нет - создаёт или обновляет запись и всё равно возвращает
sub touch(@) {
	my $sub;
	$sub = pop @_ if ref $_[$#_] eq "CODE";

	my $pk = query_id @_;
	return $pk if defined $pk;

	store @_, $sub? $sub->(): ();

	query_id @_
}

# возвращает переменную, на которой нужно установить commit, иначе происходит откат
sub START_TRANSACTION () {
	package Aion::Transaction {
		sub commit {
			my ($self) = @_;
			query::query_do("COMMIT");
			$self->{commit} = 1;
			return $self;
		}

		sub DESTROY {
			my ($self) = @_;
			query::query_do("ROLLBACK") if !$self->{commit};
		}
	}

	query::query_do("START TRANSACTION");

	bless { commit => 0 }, "Aion::Transaction";
}

1;

__END__

=encoding utf-8

=head1 NAME

Aion::Query - functional interface for accessing database mysql and mariadb

=head1 VERSION

0.0.0-prealpha

=head1 SYNOPSIS

File config.pm:

	package config;
	
	module_config Aion::Query => {
	    DRV  => "SQLite",
	    BASE => "test-base.sqlite",
	};
	
	1;



	use Aion::Query;
	
	query "CREATE TABLE author (
	    id INT PRIMARY KEY AUTOINCREMENT,
	    name STRING NOT NULL,
	    books INT NOT NULL,
	    UNIQUE name_unq (name)
	)";
	
	insert "author", name => "Pushkin A.S."     # -> 1
	touch "author", name => "Pushkin A.S."      # -> 1
	touch "author", name => "Pushkin A."        # -> 2
	
	query "SELECT count(*) FROM author"  # -> 2
	
	my @rows = query "SELECT * FROM author WHERE name like :name",
	    name => "P%",
	;
	
	\@rows # --> [{id => 1, name => "Pushkin A.S."}, {id => 2, name => "Pushkin A."}]

=head1 DESCRIPTION

Functional interface for accessing database mysql or mariadb.

=head1 SUBROUTINES

=head2 query ($query, %params)

It provide SQL (DCL, DDL, DQL and DML) queries to DBMS with quoting params.

	query "UPDATE author SET name=:name WHERE id=1", name => 'Pupkin I.' # -> 1

=head2 LAST_INSERT_ID ()

Returns last insert id.

	query "INSERT author SET name = :name", name => "Alice";
	LAST_INSERT_ID  # -> 2

=head2 quote ($scalar)

Quoted scalar for SQL-query.

	quote "abc"     # => 'abc'
	quote [1,2,"5"] # => 1,2,'5'
	
	map quote, -6, "-6", 1.5, "1.5" # --> [-6, "'-6'", 1.5, "'1.5'"]

=head2 query_prepare ($query, %param)

Replace the parameters in C<$query>. Parameters quotes by the C<quote>.

	query_prepare "INSERT author SET name = :name", name => "Alice"  # => INSERT author SET name = 'Alice'

=head2 query_do ($query)

Execution query and returns it result.

	query_do "SELECT count(*) FROM author"  # -> 2
	query_do "SELECT id FROM author WHERE id=2"  # --> [{id=>2}]

=head2 query_ref ($query, %kw)

As C<query>, but always returns a reference.

	my @res = query_ref "SELECT id FROM author WHERE id=:id", id => 2;
	\@res  # --> [[ {id=>2} ]]

=head2 query_sth ($query, %kw)

As query, but returns C<$sth>.

	my $sth = query_sth "SELECT * FROM author";
	my @rows;
	while(my $row = $sth->selectall_arrayref) {
	    push @rows, $row;
	}
	$sth->final;
	
	0+@rows  # -> 3

=head2 query_slice ($key, $val, @args)

.

	query_slice($key, $val, @args)  # -> .3

=head2 query_col ()

.

	query_col  # -> .3

=head2 query_row ()

	query_row  # -> .3

=head2 query_row_ref ()

	query_row_ref  # -> .3

=head2 query_scalar ()

	query_scalar  # -> .3

=head2 make_query_for_order ($order, $next)

	my $aion_query = Aion::Query->new;
	$aion_query->make_query_for_order($order, $next)  # -> .3

=head2 settings ($id, $value)

Устанавливает или возвращает ключ из таблицы settings

	my $aion_query = Aion::Query->new;
	$aion_query->settings($id, $value)  # -> .3

=head2 load_by_id ($tab, $pk, $fields, @options)

возвращает запись по её pk

	my $aion_query = Aion::Query->new;
	$aion_query->load_by_id($tab, $pk, $fields, @options)  # -> .3

=head2 insert ($tab, %x)

Добавляет запись и возвращает её id

	my $aion_query = Aion::Query->new;
	$aion_query->insert($tab, %x)  # -> .3

=head2 update ($tab, $id, %x)

	update($tab, $id, %x)  # -> .3

=head2 remove ($tab, $id)

Remove row from table by it id, and returns id.

	remove "author", 6  # -> 6

=head2 query_id ()

	query_id  # -> .3

=head2 stores ($tab, $rows, %opt)

	my $aion_query = Aion::Query->new;
	$aion_query->stores($tab, $rows, %opt)  # -> .3

=head2 store ()

	my $aion_query = Aion::Query->new;
	$aion_query->store  # -> .3

=head2 touch ()

Сверхмощная функция: возвращает pk, а если его нет - создаёт или обновляет запись и всё равно возвращает

	my $aion_query = Aion::Query->new;
	$aion_query->touch  # -> .3

=head2 START_TRANSACTION ()

возвращает переменную, на которой нужно установить commit, иначе происходит откат

	my $aion_query = Aion::Query->new;
	$aion_query->START_TRANSACTION  # -> .3

=head2 default_dsn ()

Default DSN for C<< DBI-E<gt>connect >>.

	default_dsn  # => 123

=head2 default_connect_options ()

DSN, USER, PASSWORD and commands after connect.

	[default_connect_options]  # --> []

=head2 base_connect ($dsn, $user, $password, $conn)

Connect to base and returns connect and it identify.

	my ($dbh, $connect_id) = base_connect("", "toor", "toorpasswd", [
	    "SET NAMES utf8",
	    "SET sql_mode='NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'",
	]);
	
	ref $dbh     # => 123
	$connect_id  # -> 123

=head2 connect_respavn ($base)

Connection check and reconnection.

	connect_respavn($base)  # -> .3

=head2 connect_restart ($base)

Рестарт коннекта

	my $aion_query = Aion::Query->new;
	$aion_query->connect_restart($base)  # -> .3

=head2 query_stop ()

возможно выполняется запрос - нужно его убить

	my $aion_query = Aion::Query->new;
	$aion_query->query_stop  # -> .3

=head2 sql_debug ($fn, $query)

.

	sql_debug($fn, $query)  # -> .3

=head1 AUTHOR

Yaroslav O. Kosmina LL<mailto:dart@cpan.org>

=head1 LICENSE

⚖ B<GPLv3>

=head1 COPYRIGHT

The Aion::Surf module is copyright © 2023 Yaroslav O. Kosmina. Rusland. All rights reserved.
