package main

/*

 Test skeleton to test REST prototype for raspiBackup (sample code how to test REST apis with gin locally or remote)

 Test can be executed as unit test using the gin engine or as a system test by using a real running server.
 Export variable HOST with the real server (e.g. http://localhost:8080) to use the server running on localhost or any other server

 Run unit test with
    go test . -v

 Run system test with
    Window1:
        go run raspiBacupRESTListener.go
    Window2:
        export HOST="http://localhost:8080"
        go test . -v

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

// Performer - executes a http request and returns the response
type Performer interface {
	PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, *[]byte, error)
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

// PerformRequest - performer implementation for unit tests using gin engine directly
func (p *UnittestHTTPClient) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, *[]byte, error) {
	t.Logf("Performing local call %s %s", requestType, path)
	req, err := http.NewRequest(requestType, path, body)
	if err != nil {
		return nil, nil, err
	}
	r := httptest.NewRecorder()
	p.Engine.ServeHTTP(r, req)
	if r != nil {
		resultBuffer, err2 := ioutil.ReadAll(r.Body)
		if err2 != nil {
			return nil, nil, err2
		}
		return r.Result(), &resultBuffer, nil
	}
	return nil, nil, err
}

// PerformRequest - performer implementation for system test using real server
func (p *SystemtestHTTPClient) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, *[]byte, error) {
	path = p.Host + path
	t.Logf("Performing remote call %s %s", requestType, path)
	req, err := http.NewRequest(requestType, path, body)
	if err != nil {
		return nil, nil, err
	}
	r, err := p.Client.Do(req)
	if err != nil {
		return nil, nil, err
	}
	if r != nil {
		resultBuffer, err2 := ioutil.ReadAll(r.Body)
		if err2 != nil {
			return nil, nil, err2
		}
		return r, &resultBuffer, nil
	}
	return nil, nil, err
}

// TestRaspiBackupDefaults - Test whether api uses correct default values for keep and type
func TestRaspiBackupDefaults(t *testing.T) {

	// SETUP test
	performer := NewPerformerFactory()

	// ENCODE request
	requestPayload := Parameters{Target: "/backup"}
	sendBytes, err := json.Marshal(requestPayload)
	require.NoError(t, err, "POST marshal failed")

	// CALL endpoint
	w, body, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup?test=1", bytes.NewBuffer(sendBytes))
	require.NoError(t, err, "POST failed")

	// DECODE response
	var responsePayload Parameters
	err = json.Unmarshal(*body, &responsePayload)
	require.NoError(t, err, "POST decode failed")

	// TEST response
	t.Logf("JSON Response: %+v", responsePayload)
	assert.Equal(t, http.StatusOK, w.StatusCode)
	requestPayload.Keep = &defaultKeep
	requestPayload.Type = &defaultType
	assert.Equal(t, requestPayload, responsePayload)
}
