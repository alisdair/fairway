package fairway

import (
	"fmt"
	"github.com/garyburd/redigo/redis"
)

type scripts struct {
	config *Config
	data   map[string]*redis.Script
}

func newScripts(config *Config) *scripts {
	return &scripts{config, make(map[string]*redis.Script)}
}

func (s *scripts) namespace() string {
	namespace := s.config.Namespace

	if len(namespace) > 0 {
		namespace = fmt.Sprint(namespace, ":")
	}

	return namespace
}

func (s *scripts) registeredQueuesKey() string {
	return fmt.Sprint(s.namespace(), "registered_queues")
}

func (s *scripts) registerQueue(queue *QueueDefinition) {
	conn := s.config.redisPool.Get()
	defer conn.Close()

	_, err := redis.Bool(conn.Do("hset", s.registeredQueuesKey(), queue.name, queue.channel))

	if err != nil {
		panic(err)
	}
}

func (s *scripts) registeredQueues() ([]string, error) {
	conn := s.config.redisPool.Get()
	defer conn.Close()
	return redis.Strings(conn.Do("hkeys", s.registeredQueuesKey()))
}

func (s *scripts) deliver(channel, facet string, msg *Msg) error {
	conn := s.config.redisPool.Get()
	defer conn.Close()

	script := s.findScript(FairwayDeliver, 1)

	_, err := script.Do(conn, s.namespace(), channel, facet, msg.json())

	return err
}

func (s *scripts) pull(queueName string) (string, *Msg) {
	conn := s.config.redisPool.Get()
	defer conn.Close()

	script := s.findScript(FairwayPull, 1)

	result, err := redis.Strings(script.Do(conn, s.namespace(), queueName))

	if err != nil {
		return "", nil
	}

	queue := result[0]
	message, _ := NewMsgFromString(result[1])

	return queue, message
}

func (s *scripts) findScript(script func() string, keyCount int) *redis.Script {
	content := script()

	if s.data[content] == nil {
		s.data[content] = redis.NewScript(keyCount, content)
	}

	return s.data[content]
}
