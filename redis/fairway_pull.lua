local namespace = KEYS[1];
local timestamp = tonumber(KEYS[2]);
local wait = tonumber(KEYS[3]);

local k = function (queue, subkey)
  return namespace .. queue .. ':' .. subkey;
end

-- Multiple queues can be passed through
-- fairway_pull. We'll loop through all 
-- provided queues, and return a message
-- from the first one that isn't empty.
for i, queue in ipairs(ARGV) do
  local active_facets  = k(queue, 'active_facets');
  local round_robin    = k(queue, 'facet_queue');
  local inflight       = k(queue, 'inflight');
  local inflight_limit = k(queue, 'limit');
  local priorities     = k(queue, 'priorities');
  local facet_pool     = k(queue, 'facet_pool');

  if wait ~= -1 then
    -- Check if any current inflight messages
    -- have been inflight for a long time.
    local inflightmessage = redis.call('zrange', inflight, 0, 0, 'WITHSCORES');

    -- If we have an inflight message and it's score
    -- is less than the current pull timestamp, reset
    -- the inflight score for the the message and resend.
    if #inflightmessage > 0 then
      if tonumber(inflightmessage[2]) <= timestamp then
        redis.call('zadd', inflight, timestamp + wait, inflightmessage[1]);
        return {queue, inflightmessage[1]}
      end
    end
  end

  -- Pull a facet from the round-robin list.
  -- This list guarantees each active facet will have a
  -- message pulled from the queue every time through..
  local facet = redis.call('rpop', round_robin);

  if facet then
    -- If we found an active facet, we know the facet
    -- has at least one message available to be pulled
    -- from it's message queue.
    local messages       = k(queue, facet);
    local inflight_total = k(queue, facet .. ':inflight');

    local message = redis.call('rpop', messages);

    if message then
      if wait ~= -1 then
        redis.call('zadd', inflight, timestamp + wait, message);
        redis.call('incr', inflight_total);
      end

      redis.call('decr', k(queue, 'length'));
    end

    -- Manage facet queue and active facets
    local current       = tonumber(redis.call('hget', facet_pool, facet)) or 0;
    local priority      = tonumber(redis.call('hget', priorities, facet)) or 1;
    local length        = redis.call('llen', messages);
    local inflight_cur  = tonumber(redis.call('get', inflight_total)) or 0;
    local inflight_max  = tonumber(redis.call('get', inflight_limit)) or 0;

    local n = 0

    -- redis.log(redis.LOG_WARNING, current.."/"..length.."/"..priority.."/"..inflight_max.."/"..inflight_cur);

    if inflight_max > 0 then
      n = math.min(length, priority, inflight_max - inflight_cur);
    else
      n = math.min(length, priority);
    end

    -- redis.log(redis.LOG_WARNING, "PULL: "..current.."/"..n);

    if n < current then
      -- redis.log(redis.LOG_WARNING, "shrinking");
      redis.call('hset', facet_pool, facet, current - 1);
    elseif n > current then
      -- redis.log(redis.LOG_WARNING, "growing");
      redis.call('lpush', round_robin, facet);
      redis.call('lpush', round_robin, facet);
      redis.call('hset', facet_pool, facet, current + 1);
    else
      -- redis.log(redis.LOG_WARNING, "maintaining");
      redis.call('lpush', round_robin, facet);
    end

    if (current == 1 and length == 0 and inflight_cur == 0 and n == 0) then
      redis.call('del', inflight_total);
      redis.call('srem', active_facets, facet);
    end

    return {queue, message};
  end
end
