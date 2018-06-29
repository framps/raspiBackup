package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

const local = true

type PostPayload struct {
	Target string `json:"target"`
	Tpe    string `json:"type"`
	Keep   int    `json:"keep"`
}

type Performer interface {
	PerformRequest(t *testing.T, r *gin.Engine, requestType string, path string, body *bytes.Buffer) *http.Response
}

type LocalPerformer struct {
	Dummy bool
}

func (p *LocalPerformer) PerformRequest(t *testing.T, r *gin.Engine, requestType string, path string, body *bytes.Buffer) *http.Response {

	req, _ := http.NewRequest(requestType, path, body)
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	t.Logf("Result %v\n", w.Body)

	return w.Result()
}

func TestRouterGroupGETNoRootExistsRouteOK(t *testing.T) {

	var performer Performer
	var r *gin.Engine
	var w *http.Response

	if local {
		// SETUP
		r = NewEngine(false, nil)
		performer = &LocalPerformer{}
	}

	var buf bytes.Buffer
	postPayload := PostPayload{Target: "/backup", Tpe: "rsync", Keep: 3}
	json.NewEncoder(&buf).Encode(&postPayload)

	// RUN
	w = performer.PerformRequest(t, r, "POST", "/v1/raspiBackup?test=1", &buf)

	// TEST
	if w.StatusCode != http.StatusOK {
		t.Errorf("Status code should be %v, was %d.", http.StatusNotFound, w.StatusCode)
	}
}
