
if ruby ./load.rb ; then

redis-cli ''
sha=`redis-cli -n 1 get nodes.create`
echo nodes.create $sha
redis-cli -n 1 evalsha $sha 0 

sha=`redis-cli -n 1 get arcs.create`
echo nodes.create $sha
redis-cli -n 1 evalsha $sha 0 0 0 
redis-cli -n 1 evalsha $sha 0 1 0 
redis-cli -n 1 evalsha $sha 0 0 1 
redis-cli -n 1 evalsha $sha 0 1 1 

#sha=`redis-cli -n 1 get Arc.delete`
#redis-cli -n 1 evalsha $sha 0 0 

fi
