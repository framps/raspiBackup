package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

type PostPayload struct {
	Target string `json:"target"`
	Tpe    string `json:"type"`
	Keep   int    `json:"keep"`
}

func PerformRequest(t *testing.T, r *gin.Engine, requestType string, path string, body *bytes.Buffer) *http.Response {

	req, _ := http.NewRequest(requestType, path, body)
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	t.Logf("Result %v\n", w.Body)

	return w.Result()
}

func TestRouterGroupGETNoRootExistsRouteOK(t *testing.T) {
	// SETUP
	r := NewEngine(false, nil)

	var buf bytes.Buffer
	postPayload := PostPayload{Target: "/backup", Tpe: "rsync", Keep: 3}
	json.NewEncoder(&buf).Encode(&postPayload)

	// RUN
	w := PerformRequest(t, r, "POST", "/v1/raspiBackup?test", &buf)

	// TEST
	if w.StatusCode != http.StatusOK {
		// If this fails, it's because httprouter needs to be updated to at least f78f58a0db
		t.Errorf("Status code should be %v, was %d.", http.StatusNotFound, w.StatusCode)
	}
}
