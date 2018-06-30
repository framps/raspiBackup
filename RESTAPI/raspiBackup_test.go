package main

/*

 Test skeleton to test REST prototype for raspiBackup

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

type UnittestHTTPClient struct {
	Engine *gin.Engine
}

type SystemtestHTTPClient struct {
	Host   string
	Client *http.Client
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

	if unitTest {
		// SETUP
		r = NewEngine(false, nil)
		performer = &UnittestHTTPClient{r}
	} else {
		performer = &SystemtestHTTPClient{host, &http.Client{}}
	}

	var sendBuffer bytes.Buffer
	postPayload := PostPayload{Target: "/backup", Tpe: "rsync", Keep: 3}
	json.NewEncoder(&sendBuffer).Encode(&postPayload)

	// RUN
	w, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup?test=1", &sendBuffer)
	require.NoError(t, err, "POST failed")

	resultBuffer, err := ioutil.ReadAll(w.Body)
	require.NoError(t, err, "POST readall failed")
	t.Logf("HTTP body received: %+v", string(resultBuffer))
	defer w.Body.Close()

	// TEST
	var responsePayload PostPayload
	err = json.Unmarshal(resultBuffer, &responsePayload)
	require.NoError(t, err, "POST decode failed")

	t.Logf("JSON Response: %+v", responsePayload)
	assert.Equal(t, http.StatusOK, w.StatusCode)
	assert.Equal(t, postPayload, responsePayload)
}
