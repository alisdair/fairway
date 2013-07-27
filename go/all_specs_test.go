package fairway

import (
	"github.com/customerio/gospec"
	"github.com/garyburd/redigo/redis"
	"testing"
)

// You will need to list every spec in a TestXxx method like this,
// so that gotest can be used to run the specs. Later GoSpec might
// get its own command line tool similar to gotest, but for now this
// is the way to go. This shouldn't require too much typing, because
// there will be typically only one top-level spec per class/feature.

func TestAllSpecs(t *testing.T) {
	r := gospec.NewRunner()

	r.Parallel = false

	r.BeforeEach = func() {
		// Load test instance of redis on port 6400
		conn, _ := redis.Dial("tcp", "localhost:6400")
		conn.Do("flushdb")
	}

	// List all specs here
	r.AddSpec(ConfigSpec)
	r.AddSpec(ConnectionSpec)
	r.AddSpec(ChanneledConnectionSpec)
	r.AddSpec(MsgSpec)
	r.AddSpec(QueueSpec)

	// Run GoSpec and report any errors to gotest's `testing.T` instance
	gospec.MainGoTest(r, t)
}
