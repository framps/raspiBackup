package main

/*

 REST prototype for raspiBackup

 See https://www.linux-tips-and-tricks.de/en/backup for details about raspiBackup

 If there is any requirement for a full blown REST API please contact the author

 To invoke raspiBackup via REST use follwing command:
     curl -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar"}' http://<raspiHost>:8080/v0.1/backup

(c) 2017 - framp at linux-tips-and-tricks dot de

*/

import (
	"fmt"
	"net/http"
	"os/exec"
	"strconv"

	"github.com/gin-gonic/gin"
)

const executable = "/usr/local/bin/raspiBackup.sh"

type parameter struct {
	Target string  `json:"target" binding:"required"`
	Type   *string `json:"type"`
	Keep   *int    `json:"keep,omitempty"`
	Mode   *string `json:"mode,omitempty"`
}

// BackupHandler - handles requests for raspiBackup
func BackupHandler(c *gin.Context) {

	var parm parameter
	err := c.BindJSON(&parm)
	if err != nil {
		msg := fmt.Sprintf("%+v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	fmt.Printf("Payload: %+v\n", parm)

	args := ""

	if parm.Type != nil {
		args = "-t " + *parm.Type
	}

	if parm.Keep != nil {
		args += "-k " + strconv.Itoa(*parm.Keep)
	}

	if parm.Mode != nil {
		args += "-P " + *parm.Mode
	}

	args += " " + parm.Target

	fmt.Println("args: " + args)
	cmd := exec.Command(executable, args)

	stdoutStderr, err := cmd.CombinedOutput()
	if err != nil {
		msg := fmt.Sprintf("%+v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": msg, "output": string(stdoutStderr[:])})
	}
}

func main() {
	api := gin.Default()

	v1 := api.Group("v0.1")
	{
		v1.POST("/backup", BackupHandler)
	}

	// curl -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar"}' http://localhost:8080/v0.1/backup

	api.Run(":8080")
}
