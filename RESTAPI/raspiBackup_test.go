package main

/*

 Test skeleton to test REST prototype for raspiBackup (sample code how to test REST apis with gin locally or remote)

 Test can be executed as unit test using the gin engine or as a system test by using a real running server.
 Export variable HOST with the real server (e.g. http://localhost:8080) to use the server running on localhost or any other server

 See https://www.linux-tips-and-tricks.de/en/backup for details about raspiBackup

 If there is any requirement for a full blown REST API please contact the author

 (c) 2018 - framp at linux-tips-and-tricks dot de

*/
import (
	"bytes"
	"encoding/json"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var (
	unitTest bool   // execute test locally in ein engine
	host     string // host to use for tests (http://localhost:8080 or http://raspibackup.remote.com)
)

type PostPayload struct {
	Target string `json:"target"`
	Tpe    string `json:"type"`
	Keep   int    `json:"keep"`
}

// Performer - executes a http request and returns the response
type Performer interface {
	PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, error)
}

// UnittestHTTPClient - performer which uses gin engine directly. No real server used
type UnittestHTTPClient struct {
	Engine *gin.Engine
}

// SystemtestHTTPClient - performer which uses a http client to contact a real running server
type SystemtestHTTPClient struct {
	Host   string
	Client *http.Client
}

// NewPerformerFactory - returns a performer depending on the environment variable HOST set or not set
func NewPerformerFactory() Performer {
	hostVar := os.Getenv("HOST")
	if len(hostVar) == 0 {
		r := NewEngine(false, nil)
		return &UnittestHTTPClient{r}
	}
	return &SystemtestHTTPClient{host, &http.Client{}}
}

func (p *UnittestHTTPClient) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, error) {
	t.Logf("Performing local call %s %s", requestType, path)
	req, err := http.NewRequest(requestType, path, body)
	if err != nil {
		return nil, err
	}
	w := httptest.NewRecorder()
	p.Engine.ServeHTTP(w, req)
	return w.Result(), nil
}

func (p *SystemtestHTTPClient) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, error) {
	path = p.Host + path
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

func TestRaspiBackup(t *testing.T) {

	// SETUP test
	performer := NewPerformerFactory()

	var sendBuffer bytes.Buffer
	postPayload := PostPayload{Target: "/backup", Tpe: "rsync", Keep: 3}
	json.NewEncoder(&sendBuffer).Encode(&postPayload)

	// RUN test
	w, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup?test=1", &sendBuffer)
	require.NoError(t, err, "POST failed")

	// READ response
	resultBuffer, err := ioutil.ReadAll(w.Body)
	require.NoError(t, err, "POST readall failed")
	t.Logf("HTTP body received: %+v", string(resultBuffer))
	defer w.Body.Close()

	// DECODE response
	var responsePayload PostPayload
	err = json.Unmarshal(resultBuffer, &responsePayload)
	require.NoError(t, err, "POST decode failed")

	// TEST results
	t.Logf("JSON Response: %+v", responsePayload)
	assert.Equal(t, http.StatusOK, w.StatusCode)
	assert.Equal(t, postPayload, responsePayload)
}
