package main

/*

 Test skeleton to test REST prototype for raspiBackup (sample code how to test REST apis with gin locally or with a remote server)

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
	"gopkg.in/jarcoal/httpmock.v1"
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
func NewPerformerFactory(t *testing.T) Performer {
	hostVar := os.Getenv("HOST")
	if len(hostVar) == 0 {
		t.Logf("Calling local gin engine")
		r := NewEngine(false, nil)
		return &UnittestHTTPClient{Engine: r}
	}
	t.Logf("Calling remote server at %s", hostVar)
	return &SystemtestHTTPClient{Host: hostVar, Client: &http.Client{}}
}

// PerformRequest - performer implementation for unit tests using local gin engine
func (p *UnittestHTTPClient) PerformRequest(t *testing.T, requestType string, path string, body *bytes.Buffer) (*http.Response, *[]byte, error) {
	t.Logf("Performing local call %s %s", requestType, path)
	req, err := http.NewRequest(requestType, path, body)
	if err != nil {
		return nil, nil, err
	}
	r := httptest.NewRecorder()
	p.Engine.ServeHTTP(r, req)
	b, err2 := ioutil.ReadAll(r.Body)
	if err2 != nil {
		return nil, nil, err2
	}
	return r.Result(), &b, nil
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
	b, err := ioutil.ReadAll(r.Body)
	defer r.Body.Close()
	if err != nil {
		return nil, nil, err
	}
	return r, &b, nil
}

// TestDefaults - Test whether api uses correct default values for keep and type
func TestDefaults(t *testing.T) {

	// SETUP test
	performer := NewPerformerFactory(t)

	// ENCODE request
	requestPayload := ParameterPayload{Target: "/backup"}
	sendBytes, err := json.Marshal(requestPayload)
	require.NoError(t, err, "POST marshal failed")

	// CALL endpoint
	w, body, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup?test=1", bytes.NewBuffer(sendBytes))
	require.NoError(t, err, "POST failed")

	// DECODE response
	var responsePayload ParameterPayload
	err = json.Unmarshal(*body, &responsePayload)
	require.NoError(t, err, "POST decode failed")

	// TEST response
	t.Logf("JSON Response: %+v", responsePayload)
	assert.Equal(t, http.StatusOK, w.StatusCode)
	requestPayload.Keep = &defaultKeep
	requestPayload.Type = &defaultType
	assert.Equal(t, requestPayload, responsePayload)
}

// TestErrors - assumtion: raspiBackup installed but there does not exist the backup path /bkup
func TestErrors(t *testing.T) {

	// SETUP test
	performer := NewPerformerFactory(t)

	// ENCODE request
	requestPayload := ParameterPayload{Target: "/bkup"}
	sendBytes, err := json.Marshal(requestPayload)
	require.NoError(t, err, "POST marshal failed")

	// CALL endpoint
	w, body, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup", bytes.NewBuffer(sendBytes))
	require.NoError(t, err, "POST failed")

	// DECODE response
	var responsePayload ErrorResponse
	err = json.Unmarshal(*body, &responsePayload)
	t.Logf("Payload received: %s", string(*body))
	require.NoError(t, err, "POST decode failed")

	// TEST response
	expectedResponse := ErrorResponse{Message: "exit status 107", Output: ""}
	t.Logf("JSON Response: %+v", responsePayload)
	assert.Equal(t, http.StatusBadRequest, w.StatusCode)
	assert.Equal(t, expectedResponse, responsePayload)
}

// TestVersion -
func TestVersion(t *testing.T) {

	// SETUP test
	performer := NewPerformerFactory(t)

	// CALL endpoint
	var buffer bytes.Buffer
	w, body, err := performer.PerformRequest(t, "GET", "/v1/raspiBackup", &buffer)
	require.NoError(t, err, "GET failed")

	// DECODE response
	var responsePayload VersionResponse
	t.Logf("Payload: %s", string(*body))
	err = json.Unmarshal(*body, &responsePayload)
	t.Logf("Payload received: %s", string(*body))
	require.NoError(t, err, "GET decode failed")

	// TEST response
	assert.Equal(t, http.StatusOK, w.StatusCode)
	t.Logf("JSON Response: %+v", responsePayload)
	assert.NotZero(t, responsePayload.CommitDate)
	assert.NotZero(t, responsePayload.CommitTime)
	assert.NotZero(t, responsePayload.CommitSHA)
	assert.NotZero(t, responsePayload.Version)
}

// TestMock -
func TestMock(t *testing.T) {

	type response struct {
		Msg string
	}

	// mock only works if a http client is used
	oldHost := os.Getenv("HOST")
	os.Setenv("HOST", "http://localhost:8080")
	defer os.Setenv("HOST", oldHost)

	httpmock.Activate()
	httpmock.RegisterNoResponder(httpmock.InitialTransport.RoundTrip) // non mocked urls are passed through
	defer httpmock.DeactivateAndReset()

	rsp := ExecutionResponse{Output: "Done"}

	httpmock.RegisterResponder("POST", "/v1/raspiBackup",
		func(req *http.Request) (*http.Response, error) {
			t.Logf("MOCKED REQUEST served")
			resp, err := httpmock.NewJsonResponse(200, rsp)
			if err != nil {
				return httpmock.NewJsonResponse(500, ErrorResponse{Message: "Failure", Output: "???"})
			}
			return resp, nil
		},
	)

	// SETUP test
	performer := NewPerformerFactory(t)

	// ENCODE request
	requestPayload := ParameterPayload{Target: "/bkup"}
	sendBytes, err := json.Marshal(requestPayload)
	require.NoError(t, err, "POST marshal failed")

	// CALL endpoint
	w, body, err := performer.PerformRequest(t, "POST", "/v1/raspiBackup", bytes.NewBuffer(sendBytes))
	require.NoError(t, err, "POST failed")

	// DECODE response
	var responsePayload ExecutionResponse
	t.Logf("Payload: %s", string(*body))
	err = json.Unmarshal(*body, &responsePayload)
	t.Logf("Payload received: %s", string(*body))
	require.NoError(t, err, "POST decode failed")

	// TEST response
	assert.Equal(t, http.StatusOK, w.StatusCode)
	expectedResponse := ExecutionResponse{Output: "Done"}
	t.Logf("JSON Response: %+v", responsePayload)
	assert.Equal(t, expectedResponse, responsePayload)
}

// TestParam -
func TestParam(t *testing.T) {

	type response struct {
		Msg string
	}

	// mock only works if a http client is used
	//oldHost := os.Getenv("HOST")
	//os.Setenv("HOST", "http://localhost:8080")
	//defer os.Setenv("HOST", oldHost)

	httpmock.Activate()
	httpmock.RegisterNoResponder(httpmock.InitialTransport.RoundTrip) // non mocked urls are passed through
	defer httpmock.DeactivateAndReset()

	httpmock.RegisterResponder("GET", "/v1/raspiBackup/param/:param",
		func(req *http.Request) (*http.Response, error) {
			t.Logf("MOCKED REQUEST served: %s", req.URL)
			resp, err := httpmock.NewJsonResponse(200, nil)
			if err != nil {
				return httpmock.NewJsonResponse(500, ErrorResponse{Message: "Failure", Output: "???"})
			}
			return resp, nil
		},
	)

	// SETUP test
	performer := NewPerformerFactory(t)

	// CALL endpoint
	var b []byte
	w, body, err := performer.PerformRequest(t, "GET", "/v1/raspiBackup/param/42%2F4711%2f1147", bytes.NewBuffer(b))
	require.NoError(t, err, "GET failed")

	// DECODE response
	type parmResponse struct {
		Param    string
		Exists   bool
		Optional string
	}

	var r parmResponse
	err = json.Unmarshal(*body, &r)
	require.NoError(t, err, "unmarshal failed")
	t.Logf("Payload received: %s", string(*body))

	// TEST response
	assert.Equal(t, r.Param, "42")
	assert.Equal(t, r.Optional, "/4711/1147")
	assert.Equal(t, http.StatusOK, w.StatusCode)
	t.Logf("JSON Response: %+v", r)
}
