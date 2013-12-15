

function color {
	echo -ne "\033[$1m$2"
}

echo "`color '1;41;33'`Flush`color '0;31'` `redis-cli -n 1 flushall` `color '0'`" 

if ruby ./load.rb ; then

color '0;44;97' "#                        `color 0`\n"
color '0;44;97' "#       `color '0;44;97'`TESTS !!!!       `color '0;44;97;'``color 0`\n"
color '0;44;97' "#                        `color 0`\n"

function failure () {
	echo -e "`color 1 ` * `color '1;31' ` Failure Scenario `color 0 ` $@ "   
}
function success () {
	echo -e "`color 1 ` * `color '1;32' ` Success Scenario `color 0 ` "   $@
}

function test_check {
	exp=$1
	ret=$2
	if [ "$exp" = "$ret" ]; then
		echo "`color '1;32;99'` ! `color '0;1;32'`Test Pass`color 0`" $ret
	else
		echo "`color '1;31;99;5'` ! `color '0;1;41'`Test FAIL `color '5'`!!! `color '0;31'`$ret`color 0` != $exp "
		exit -1
	fi
}


color '00;44;97' "### nodes.create `color 0`\n"

sha=`redis-cli -n 1 get nodes.create`
nodes_create=$sha
echo -e "`color "103;1"`nodes.create`color "0;"` $sha"

success "Create Node"
n1=`redis-cli -n 1 evalsha $sha 0` 
test_check 0 $?
success "Create Node"
n2=`redis-cli -n 1 evalsha $sha 0` 
test_check 0 $?
success "Create Node"
n3=`redis-cli -n 1 evalsha $sha 0` 
test_check 0 $?
success "Create Node"
n4=`redis-cli -n 1 evalsha $sha 0` 
test_check 0 $?

color '00;44;97' "### arcs.create `color 0`\n"

sha=`redis-cli -n 1 get arcs.create`
arcs_create=`redis-cli -n 1 get arcs.create`
echo -e "`color "103;1"`arcs.create`color "0;"` $sha"
failure both nodes must exist, 
redis-cli -n 1 evalsha $sha 0 0 0 
redis-cli -n 1 evalsha $sha 0 $n1 0 
redis-cli -n 1 evalsha $sha 0 0 $n1 

failure nodes must be different  not $n1 and $n1
redis-cli -n 1 evalsha $sha 0 $n1 $n1 
success join nodes $n1 and $n2
redis-cli -n 1 evalsha $sha 0 $n1 $n2 
failure nodes already linked
redis-cli -n 1 evalsha $sha 0 $n1 $n2
success create arc
a2=`redis-cli -n 1 evalsha $sha 0 $n2 $n3`
echo $a2
success create arc
a3=`redis-cli -n 1 evalsha $sha 0 $n3 $n1`
echo $a3
success create arc
a4=`redis-cli -n 1 evalsha $sha 0 $n4 $n1`
echo $a4

color '00;44;97' "### arcs.delete `color 0`\n" 

sha=`redis-cli -n 1 get arcs.delete`
echo -e "`color "103;1"`arcs.delete`color "0;"` $sha"
success delete arc $a4
redis-cli -n 1 evalsha $sha 0 $a4
failure delete arc $a4 "(does not exist)"
redis-cli -n 1 evalsha $sha 0 $a4

color '00;44;97' "### nodes.delete`color 0`\n" 

sha=`redis-cli -n 1 get nodes.delete`
nodes_delete=$sha
echo -e "`color "103;1"`nodes.delete`color "0;"` $sha"
success delete node $n4 "( now unlinked )"
redis-cli -n 1 evalsha $sha 0 $n4
failure delete node $n4 "(does not exist)"
redis-cli -n 1 evalsha $sha 0 $n4
failure delete node $n1 "(arcs link)"
redis-cli -n 1 evalsha $sha 0 $n1

color '00;44;97' "### things.create `color 0`\n" 

sha=`redis-cli -n 1 get things.create`
things_create=$sha
echo -e "`color "103;1"`things.create `color "0;"` $sha"
failure "Create a thing ( bad node 0 )"
redis-cli -n 1 evalsha $sha 0 0
success "Create a thing (valid node $n1)"
t1=`redis-cli -n 1 evalsha $sha 0 $n1`
echo "t1=$t1"
nodes=""
nodes="$nodes`redis-cli -n 1 zrange nodes 0 -1` "
success "Create a thing on each valid random node ( $nodes )"
for node  in $nodes; do
	t2=`redis-cli -n 1 evalsha $sha 0 $node`
	echo "t2=$t2"
done

color '00;44;97' "### things.delete `color 0`\n" 
sha=`redis-cli -n 1 get things.delete`
echo -e "`color "0;103;"`things.delete `color "0;"` $sha"

failure delete thing 0 "(does not exist)"
redis-cli -n 1 evalsha $sha 0 0

success delete thing $t2 
redis-cli -n 1 evalsha $sha 0 $t2

color '00;44;97' "### nodes.delete + thing `color 0`\n" 
n=`redis-cli -n 1 evalsha $nodes_create 0` 
t=`redis-cli -n 1 evalsha $things_create 0 $n`
failure delete node $n "(inhabitant)"
redis-cli -n 1 evalsha $nodes_delete 0 $n
success delete thing $t 
redis-cli -n 1 evalsha $sha 0 $t
success delete now uninhabitaed node $n
redis-cli -n 1 evalsha $nodes_delete 0 $n

exit

color '00;44;97' "### things.move `color 0`\n" 
sha=`redis-cli -n 1 get things.move`
things_move=$sha
echo -e "`color '0;103'`things.move `color 0` $sha"
failure $t1 cannot reach arc $a2
redis-cli -n 1 evalsha $things_move 0 $t1 $a2
success move $t1 through $a3
redis-cli -n 1 evalsha $things_move 0 $t1 $a3


fi
