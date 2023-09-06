package Aion::Query;
use common::sense;

our $VERSION = "0.0.0-prealpha";

use config {
    base => 'base',
    user => 'root',
    password => 123,
    host => undef,
    port => undef,
    sock => undef,
};

# Коннекты
sub base_connect {
	my ($config) = @_;
	my $base = DBI->connect($config->[0], $config->[1], $config->[2], {
		RaiseError => 1,
		PrintError => 0,
		$config->[0] =~ /^DBI:mysql/ ? (mysql_enable_utf8 => 1): (),
	}) or die "Connect to db failed";

	$base->do($_) for @{$config->[3]};
	return $base if !wantarray;
	my ($base_connection_id) = $base->selectrow_array("SELECT connection_id()");
	return $base, $base_connection_id;
}

sub connect_respavn {
	my ($base) = @_;
	$base->disconnect, undef $base if $base and !$base->ping;
	($_[0], $_[1]) = base_connect($main_config::mysql) if !$base;
	return;
}

sub connect_restart {
	my ($base) = @_;
	$base->disconnect if $base;
	$_[0] = base_connect($main_config::mysql);
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
	my $signal = base_connect($main_config::mysql);
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
	print STDERR $msg, "\n" if $main_config::sql_debug ~~ [1, 3];
}

sub debug_html {
	join "", map { ("<p class='debug'>", to_html($_), "</p>\n") } @DEBUG;
}

sub debug_text {
	return "" if !@DEBUG;
	join "", map { "$_\n\n" } @DEBUG, "";
}

sub debug_array {
	return if !@DEBUG;
	$_[0]->{SQL_DEBUG} = \@DEBUG;
	return;
}


sub LAST_INSERT_ID() {
	query_scalar("SELECT LAST_INSERT_ID()");
}

# Преобразует в строку
sub to_str($) {
	local($_) = @_;
	s/[\\']/\\$&/g;
	s/^(.*)\z/'$1'/s;
	$_
}

# Преобразует в бинарную строку принятую в MYSQL
sub to_hex_str($) {
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
sub recode_cp1251 {
	my ($s) = @_;
	our $CIF;
	$s =~ s/°|[^\Q$CIF\E]/"°${\ to_radix(ord $&, 254) }\x7F"/ge;
	$s
}

sub quote($);
sub quote($) {
	my ($k) = @_;

	!defined($k)? "NULL":
	ref $k eq "ARRAY" && ref $k->[0] eq "ARRAY"? join(", ", map { join "", "(", join(", ", map { quote($_) } @$_), ")" } @$k):
	ref $k eq "ARRAY"? join("", join(", ", map { quote($_) } @$k)):
	ref $k eq "HASH"? join(" ", map { join " ", "WHEN", quote($_), "THEN", quote($k->{$_}) } sort keys %$k):
	ref $k eq "REF" && ref $$k eq "HASH"? join(", ", map { join "", $_, " = ", quote($$k->{$_}) } sort keys %$$k):
	ref $k eq "SCALAR"? $$k:
	Scalar::Util::blessed($k)? $k:
	$k =~ /^-?(0|[1-9]\d*)(\.\d+)?\z/an && B::svref_2object(\$k) ne "B::PV"? $k:
	!utf8::is_utf8($k)? (
		$k =~ /[\x80-\xFF]/a ? to_hex_str($k): #$base->quote($k, DBI::SQL_BINARY):
			to_str($k)
	):
	to_str(recode_cp1251($k))
}

sub query_prepare (@) {
	my ($query, %param) = @_;

	$query =~ s!^[ \t]*(\w+)>>(.*\n?)!$param{$1}? $2: ""!mge;
	#$query =~ s!^[ \t]*(\w+)\*>(.*\n?)!$param{$1}? join("", map {  } @{$param{$1}}): ""!mge;
	$query =~ s!:([a-z_]\w*)! exists $param{$1}? quote($param{$1}): die "Не передан параметр :$1 в запрос $query"!ige;

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
	die "Записи с $tab.id=$id — нет." if !query "DELETE FROM $tab WHERE id=:id", id=>$id;
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
