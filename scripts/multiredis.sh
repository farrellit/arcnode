alias echo=echo -e
for i in `seq 1 4`; do
	p=$((6379 + $i))
	/usr/sbin/redis-server --port $p >/tmp/redis-logs 2>&1 &
	sleep .25
	redis-cli -p  $p slaveof 127.0.0.1 6379
done
s="`openssl rand -base64 256`"
echo "$s"
echo -n $s|md5sum
echo -e "\033[1m" "Actual md5:\033[0m `echo -n "$s" |md5sum `"
redis-cli --raw "set" "s" "$s"
for i in `seq 0 4`; do
	p=$((6379+i))
	echo -e "\033[1m" "$p:" "\033[0m" "`redis-cli --raw -p $p get s|md5sum`" 
done
