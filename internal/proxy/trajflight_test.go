package proxy

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestTrajFlightGroupCoalescesConcurrentCalls(t *testing.T) {
	g := &trajFlightGroup{calls: make(map[string]*trajFlightCall)}
	var calls int32
	release := make(chan struct{})
	want := &upstreamTrajectoryResp{}

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			got, err := g.do("c1", func() (*upstreamTrajectoryResp, error) {
				atomic.AddInt32(&calls, 1)
				<-release
				return want, nil
			})
			if err != nil || got != want {
				t.Errorf("unexpected result: %v %v", got, err)
			}
		}()
	}
	time.Sleep(50 * time.Millisecond)
	close(release)
	wg.Wait()

	if n := atomic.LoadInt32(&calls); n != 1 {
		t.Fatalf("expected 1 upstream call, got %d", n)
	}
	if len(g.calls) != 0 {
		t.Fatalf("flight map not cleaned up")
	}
}

func TestFetchUpstreamTrajectoryStreamsLargePayload(t *testing.T) {
	// Build a >9MB trajectory JSON payload (exceeds 8MB raw cache threshold) to verify
	// the streaming json.NewDecoder path parses cleanly without truncation.
	padding := strings.Repeat("a", 9*1024*1024)
	payload := `{"status":"CASCADE_RUN_STATUS_IDLE","trajectory":{"cascadeId":"large-stream-test","summary":"Large Session","steps":[{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","plannerResponse":{"response":"` + padding + `"}}]}}`

	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(payload))
	}))
	defer srv.Close()

	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("parse server url: %v", err)
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		t.Fatalf("parse server port: %v", err)
	}

	p := &Proxy{
		longClient: srv.Client(),
	}
	got, err := p.fetchUpstreamTrajectoryUncached(context.Background(), "large-stream-test", port, "tok")
	if err != nil {
		t.Fatalf("expected large trajectory to stream-decode without error, got: %v", err)
	}
	if got == nil || got.Trajectory.Summary != "Large Session" || len(got.Trajectory.Steps) != 1 {
		t.Fatalf("unexpected decoded trajectory: %+v", got)
	}
	ClearTrajectoryCache("large-stream-test")
}
