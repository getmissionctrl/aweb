package main

import (
	"sync"

	"github.com/awebai/aw/natstransport"
)

// natsOnce lazily initializes a NATS transport from AWEB_NATS_URL.
// Returns nil if NATS is not configured or unavailable.
var (
	natsOnce      sync.Once
	natsTransport *natstransport.Transport
)

func getNatsTransport(teamID, alias string) *natstransport.Transport {
	natsOnce.Do(func() {
		t, err := natstransport.ConnectFromEnv(teamID, alias)
		if err != nil {
			debugLog("NATS transport: %v", err)
			return
		}
		natsTransport = t
	})
	return natsTransport
}

func closeNatsTransport() {
	if natsTransport != nil {
		natsTransport.Close()
	}
}
