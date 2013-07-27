package fairway

import (
	"fmt"
	"github.com/customerio/gospec"
	. "github.com/customerio/gospec"
	"github.com/garyburd/redigo/redis"
)

func ChanneledConnectionSpec(c gospec.Context) {
	// Load test instance of redis on port 6400
	config := NewConfig("localhost:6400", 2)
	config.AddQueue("myqueue", "typea")
	config.AddQueue("myqueue2", "typeb")

	conn := NewChanneledConnection(config, func(message *Msg) string {
		channel, _ := message.Get("type").String()
		return fmt.Sprint("channel:type", channel, ":channel")
	})

	c.Specify("Deliver", func() {
		c.Specify("only queues up message for matching queues", func() {
			r := config.redisPool.Get()
			defer r.Close()

			count, _ := redis.Int(r.Do("llen", "fairway:myqueue:default"))
			c.Expect(count, Equals, 0)
			count, _ = redis.Int(r.Do("llen", "fairway:myqueue2:default"))
			c.Expect(count, Equals, 0)

			msg, _ := NewMsg(map[string]string{"type": "a"})

			conn.Deliver(msg)

			count, _ = redis.Int(r.Do("llen", "fairway:myqueue:default"))
			c.Expect(count, Equals, 1)
			count, _ = redis.Int(r.Do("llen", "fairway:myqueue2:default"))
			c.Expect(count, Equals, 0)
		})
	})
}
