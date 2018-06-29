package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
)

var (
	unitTest bool   // execute test locally
	host     string // host to use for tests
)

type PostPayload struct {
	Target string `json:"target"`
	Tpe    string `json:"type"`
	Keep   int    `json:"keep"`
}

type Performer interface {
	PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, error)
}

type LocalPerformer struct {
	Engine *gin.Engine
}

type RemotePerformer struct {
	Host   string
	Client *http.Client
}

func (p *LocalPerformer) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, error) {
	t.Logf("Performing local call %s %s", requestType, path)
	req, err := http.NewRequest(requestType, path, body)
	if err != nil {
		return nil, err
	}
	w := httptest.NewRecorder()
	p.Engine.ServeHTTP(w, req)
	return w.Result(), nil
}

func (p *RemotePerformer) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, error) {
	path = "http://" + p.Host + path
	t.Logf("Performing remote call %s %s", requestType, path)
	req, err := http.NewRequest(requestType, path, body)
	if err != nil {
		return nil, err
	}
	w, err := p.Client.Do(req)
	if err != nil {
		return nil, err
	}
	return w, nil
}

func setup() {
	hostVar := os.Getenv("HOST")
	if len(hostVar) == 0 {
		unitTest = true
	} else {
		host = hostVar
		unitTest = false
	}
}

func TestRaspiBackup(t *testing.T) {

	setup()

	var performer Performer
	var r *gin.Engine
	var w *http.Response

	if unitTest {
		// SETUP
		r = NewEngine(false, nil)
		performer = &LocalPerformer{r}
	} else {
		performer = &RemotePerformer{host, &http.Client{}}
	}

	var buf bytes.Buffer
	postPayload := PostPayload{Target: "/backup", Tpe: "rsync", Keep: 3}
	json.NewEncoder(&buf).Encode(&postPayload)

	// RUN
	w, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup?test=1", &buf)
	if err != nil {
		t.Errorf("Error occured: %s", err)
		return
	}

	// TEST
	if w.StatusCode != http.StatusOK {
		t.Errorf("Status code should be %v, was %d.", http.StatusOK, w.StatusCode)
	}
}
