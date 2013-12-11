
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
		echo "`color '1;32;99'` ! `color '0;1;32'`Test Pass`color 0`"
	else
		echo "`color '1;31;99;5'` ! `color '0;1;41'`Test FAIL `color '5'`!!! `color '0;31'`$ret`color 0` != $exp "
		exit -1
	fi
}

color '00;44;97' "### nodes.create `color 0`\n"

sha=`redis-cli -n 1 get nodes.create`
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
redis-cli -n 1 evalsha $sha 0 $n2 $n3
success create arc
a3=`redis-cli -n 1 evalsha $sha 0 $n3 $n1`
success create arc
a4=`redis-cli -n 1 evalsha $sha 0 $n4 $n1`


color '00;44;97' "### arcs.delete `color 0`\n" 

sha=`redis-cli -n 1 get arcs.delete`
echo -e "`color "103;1"`arcs.delete`color "0;"` $sha"
success delete arc $a4
redis-cli -n 1 evalsha $sha 0 $a4
failure delete arc $a4 "(does not exist)"
redis-cli -n 1 evalsha $sha 0 $a4

color '00;44;97' "### nodes.delete`color 0`\n" 

sha=`redis-cli -n 1 get nodes.delete`
echo -e "`color "103;1"`nodes.delete`color "0;"` $sha"
success delete node $n4 "( now unlinked )"
redis-cli -n 1 evalsha $sha 0 $n4
failure delete node $n4 "(does not exist)"
redis-cli -n 1 evalsha $sha 0 $n4

failure delete node $n1 "(arcs link)"
redis-cli -n 1 evalsha $sha 0 $n1

fi
