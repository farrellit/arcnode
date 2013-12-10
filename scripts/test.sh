
function color {
	echo -ne "\033[$1m$2"
}

echo "`color '1;41;33'`Flush`color '0;31'` `redis-cli -n 1 flushall` `color '0'`" 

if ruby ./load.rb ; then

color '0;44;97' "#                        `color 0`\n"
color '0;44;97' "#       `color '0;5;44;97'`TESTS !!!!       `color '0;44;97;'``color 0`\n"
color '0;44;97' "#                        `color 0`\n"

function failure () {
	echo -e "`color 1 ` * `color '1;31' ` Failure Scenario `color 0 ` "   $@
}
function success () {
	echo -e "`color 1 ` * `color '1;32' ` Success Scenario `color 0 ` "   $@
}

sha=`redis-cli -n 1 get nodes.create`
echo -e "`color "103;1"`nodes.create`color "0;"` $sha"
success "Create Node"
n1=`redis-cli -n 1 evalsha $sha 0` 
success "Create Node"
n2=`redis-cli -n 1 evalsha $sha 0` 
success "Create Node"
n3=`redis-cli -n 1 evalsha $sha 0` 

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
success
redis-cli -n 1 evalsha $sha 0 $n2 $n3
success
redis-cli -n 1 evalsha $sha 0 $n3 $n1


#sha=`redis-cli -n 1 get Arc.delete`
#redis-cli -n 1 evalsha $sha 0 0 

fi
