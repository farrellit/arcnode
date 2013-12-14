#!/bin/bash
num=1024
redis-cli -n 1 flushall
ruby ./load.rb
sha=`redis-cli -n 1 get nodes.create`
echo "nodes.create: $sha"
for i in `seq 1 $num`; do 
	redis-cli -n 1 evalsha $sha 0 
done
echo "Created $num nodes"

